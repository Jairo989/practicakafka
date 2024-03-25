#!/usr/bin/env python

import json
from kafka import KafkaConsumer

consumer = KafkaConsumer('tweets_sin_analizar',
                         group_id='grupocomprobador',
                         bootstrap_servers='127.0.0.1:9092',
                         auto_offset_reset='earliest')

for message in consumer:
    if message.key is not None:
        key_decoded = message.key.decode('utf-8')
    else:
        key_decoded = "None"

    try:
        value_decoded = message.value.decode('utf-8')
    except UnicodeDecodeError:
        value_decoded = message.value.decode('utf-8', 'ignore')

    #print(f"{message.topic}:{message.partition}:{message.offset}: key={key_decoded} value={value_decoded}")
