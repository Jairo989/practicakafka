from kafka import KafkaConsumer, KafkaProducer
import json
import re
import uuid
from textblob import TextBlob

def get_tweet_length(texto):
    return len(texto)

consumer = KafkaConsumer(
    'tweets_analizados',
    bootstrap_servers='127.0.0.1:9092',
    auto_offset_reset='earliest',
    value_deserializer=lambda x: json.loads(x.decode('utf-8'))
)

producer = KafkaProducer(
    bootstrap_servers='127.0.0.1:9092',
    key_serializer=str.encode,
    value_serializer=lambda x: json.dumps(x).encode('utf-8')
)

total_polarity = 0
total_tweets = 0

for message in consumer:
    try:
        value_decoded = message.value['texto']
        sentimiento = message.value['sentimiento']
        tweet_length = len(value_decoded)

        analysis = TextBlob(value_decoded)
        polarity = analysis.sentiment.polarity

        total_polarity += polarity
        total_tweets += 1

        avg_polarity = total_polarity / total_tweets

        processed_message = {
            'texto': value_decoded,
            'sentimiento': sentimiento,
            'tweet_length': tweet_length,
            'polaridad': polarity,
            'avg_polarity': avg_polarity
        }
        print(f"Processed message: {processed_message}")

        key = str(uuid.uuid4()) if message.key is None else message.key.decode('utf-8')
        producer.send('tweets_procesados', key=key, value=processed_message)

    except Exception as e:
        print(f"Error al procesar el mensaje: {e}")

