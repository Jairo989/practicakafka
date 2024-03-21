#!/bin/bash

# Ejecutar docker-compose

entorno="/mnt/c/practicakafka/"
dataset="/mnt/c/practicakafka/kafkaconnect/tweets/"
logs_APIS="/mnt/c/practicakafka/consumerproducerAPI/logs/"
APIS="/mnt/c/practicakafka/consumerproducerAPI/"



docker-compose -f entorno/docker-compose.yml up -d

echo "Esperando a que los contenedores se levanten...Puede tardar entre 2-3 minuntos aproximadamente."
while ! docker logs connect 2>&1 | grep -q "INFO Kafka Connect started (org.apache.kafka.connect.runtime.Connect)"; do
    sleep 1
done

echo "Todos los contenedores están levantados y la red está lista."
sleep 5

# Configurar kafka connect
echo "Conectandose a Kafka Connect"

docker exec -it connect bash -c '
  echo "Creando directorios necesarios para su correcto funcionamiento..."	
  mkdir -p /tmp/input /tmp/finerr /tmp/finok &&
  echo "Directorios creados"
  sleep 5
  echo "Iniciando instalacion kafka-connect-spooldir:2.0.65..."
  confluent-hub install --no-prompt jcustenborder/kafka-connect-spooldir:2.0.65 &&
  echo "Instalación COMPLETADA." &&
  exit	
 '

sleep 5 

#Copiar dataset de tweets
echo "Copiando dataset de twitter a Kafka Connect..."

docker cp "$dataset"/twitter.txt connect:/tmp/input/twitter.txt

echo "Dataset de tweets preparados en KafkaConnect."
sleep 5

# Reiniciar el contenedor Connect
echo "Reiniciando contenedor de KafkaConnect..."
docker restart connect

echo "Esperando a que Kafka Connect se reinicie...puede tardar 2-3 minutos aproximadamente."
echo " Puede comprobarse el estado del reinicio ejecuatando \"docker logs connect -f\"  desde otro terminal."
while ! docker logs connect 2>&1 | grep -q "INFO Kafka Connect started (org.apache.kafka.connect.runtime.Connect)"; do
    sleep 1
done

echo "Contenedor de KafkaConnect reiniciado."
sleep 5


# Configuración de topics
echo "Conectandose a broker..."
sleep 5

echo " Comprobando que los procesos APIS no están en ejecución..."
# Buscar los PID de los procesos de Python que coinciden con los nombres de los scripts
pid_analizador=$(ps axu | grep 'python3' | grep 'Analizador.py' | grep 'datahack' | grep -v grep | awk '{print $2}')
pid_procesador=$(ps axu | grep 'python3' | grep 'Procesador.py' | grep 'datahack' | grep -v grep | awk '{print $2}')

# Verificar si se encontraron los procesos
if [ -n "$pid_analizador" ] || [ -n "$pid_procesador" ]; then
    echo "Se encontraron procesos de Python en ejecución:"
    if [ -n "$pid_analizador" ]; then
        echo "PID del Analizador: $pid_analizador"
        echo "Matando proceso del Analizador (PID: $pid_analizador)"
        kill -9 "$pid_analizador"
    fi
    if [ -n "$pid_procesador" ]; then
        echo "PID del Procesador: $pid_procesador"
        echo "Matando proceso del Procesador (PID: $pid_procesador)"
        kill -9 "$pid_procesador"
    fi
    echo "Procesos de Python han sido terminados."
else
    echo "No se encontraron procesos de Python en ejecución."
fi

docker exec -it broker bash -c '
echo "Creando topics del sistema..."
kafka-topics --bootstrap-server broker:9092 --create --topic tweets_sin_analizar -partitions 1 --replication-factor 1 --config max.message.bytes=64000 --config flush.messages=5 &&
 kafka-topics --bootstrap-server broker:9092 --create --topic tweets_analizados -partitions 1 --replication-factor 1 --config max.message.bytes=64000 --config flush.messages=5 &&
 kafka-topics --bootstrap-server broker:9092 --create --topic tweets_procesados -partitions 1 --replication-factor 1 --config max.message.bytes=64000 --config flush.messages=5 &&
exit
'
sleep 10

echo "Creación de los topics COMPLETADA." 

sleep 15 

# Ejecutar los comandos dentro del contenedor ksqldb-cli

echo "Conectandose a ksqldb-cli..."
echo "Creando Stream \"tweets_procesados_stream\"..."
docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 <<EOF
CREATE STREAM tweets_procesados_stream (texto VARCHAR, sentimiento VARCHAR, tweet_length INT, polaridad DOUBLE, avg_polarity DOUBLE) WITH (KAFKA_TOPIC='tweets_procesados', VALUE_FORMAT='JSON');
EOF

echo "Stream \"tweets_procesados_stream\" creado."
echo "Mostrando Stream \"tweets_procesados_stream\"..."

docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 <<EOF
SHOW STREAMS;
EOF

sleep 10

echo "Creando tabla \"Sentimientos\"..."

docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 <<EOF
CREATE TABLE sentimientos AS SELECT sentimiento, COUNT(*) AS Numero_Tweets, AVG(polaridad) AS Media_polaridad FROM tweets_procesados_stream GROUP BY sentimiento EMIT CHANGES;
EOF

echo "Tabla \"sentimientos\" creada."
echo "Mostrando tabla \"sentimientos\"..."

docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 <<EOF
SHOW TABLES;
EOF

sleep 10

# Comprobar si textblob está instalado
if pip show textblob &> /dev/null; then
    echo "Textblob ya está instalado."
else
    echo "Textblob no está instalado. Instalando..."
    pip install textblob --quiet

    # Esperar a que la instalación finalice
    sleep 30

    # Verificar nuevamente si textblob está instalado
    if pip show textblob &> /dev/null; then
        echo "Instalación de Textblob completada."
    else
        echo "Error: La instalación de Textblob ha fallado."
    fi
fi

# Arranca las APIS

# Verificar si el directorio de logs existe
if [ -d "$logs_APIS" ]; then
    echo "El directorio de logs ya existe."
else
    # Crear el directorio de logs si no existe
    mkdir -p "$logs_APIS"
    echo "Se ha creado el directorio de logs."
fi

sleep 5

echo "Arrancando APIS..."

if ! pgrep -f "python3 $APIS/Analizador.py" >/dev/null; then
    echo "Analizador.py no está en ejecución. Iniciando..."
    python3 "$APIS"/Analizador.py > "$logs_APIS"/Analizador.log 2>&1 &
else
    echo "Analizador.py está en ejecución."
fi

if ! pgrep -f "python3 $APIS/Procesador.py" >/dev/null; then
    echo "Procesador.py no está en ejecución. Iniciando..."
    python3 "$APIS"/Procesador.py > "$logs_APIS"/Procesador.log 2>&1 &
else
    echo "Procesador.py está en ejecución."
fi

# Verificar el estado de ejecución de los scripts
if [ $? -eq 0 ]; then
    echo "Las APIS se han iniciado correctamente."
else
    echo "Error al iniciar las APIS."
fi

sleep 5
echo "DESPLIEGUE COMPLETADO!!!!"

