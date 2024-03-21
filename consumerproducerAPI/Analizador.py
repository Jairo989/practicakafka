import json
import re
from kafka import KafkaConsumer, KafkaProducer
from textblob import TextBlob
def clean_text(texto):
    cleaned_text = re.sub(r'^[�>\\|"\~]', '', texto)
    cleaned_text = re.sub(r'[\x00-\x1f\x7f-\x9f]', '', cleaned_text)
    return cleaned_text

consumer = KafkaConsumer(
    'tweets_sin_analizar',
    group_id='grupoAnalizador',
    bootstrap_servers='127.0.0.1:9092',
    auto_offset_reset='earliest'
)

producer = KafkaProducer(
    bootstrap_servers=['127.0.0.1:9092'],
    value_serializer=lambda x: json.dumps(x).encode('utf-8')
)

for message in consumer:
    try:
        value_decoded = message.value.decode('utf-8')
        clean_value = clean_text(value_decoded)
    except UnicodeDecodeError:
        clean_value = clean_text(message.value.decode('utf-8', 'ignore'))

    analysis = TextBlob(clean_value)
    sentimiento = "neutro"
    if analysis.sentiment.polarity > 0:
        sentimiento = "positivo"
    elif analysis.sentiment.polarity < 0:
        sentimiento = "negativo"

    print(f"{message.topic}:{message.partition}:{message.offset}: key={'None' if message.key is None else message.key.decode('utf-8')} sentimiento={sentimiento} value={clean_value}")

    result_message = {'texto': clean_value, 'sentimiento': sentimiento}
    producer.send('tweets_analizados', value=result_message)

