#!/bin/bash

# Jupyter Lab startup script for EMR 7.x with Hail
# Configures Spark 3.5.x integration and starts JupyterLab

export SPARK_HOME=/usr/lib/spark
export HAIL_HOME=/opt/hail-on-AWS-spot-instances

# Use Python 3.11 for Hail (system python3 remains unchanged for EMR operations)
export PYSPARK_PYTHON=/usr/bin/python3.11
export PYSPARK_DRIVER_PYTHON=/usr/bin/python3.11

# For EMR 7.x with Spark 3.5.x, Hail uses a wheel-based installation
# PYTHONPATH setup for Spark
export PYTHONPATH="$SPARK_HOME/python:${SPARK_HOME}/python/lib/py4j-*.zip:$PYTHONPATH"
echo "PYTHONPATH: ${PYTHONPATH}"

echo "PYSPARK_PYTHON: ${PYSPARK_PYTHON}"

# Java 11 is required for Hail 0.2.137+
export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64
export PATH=$JAVA_HOME/bin:$PATH

# EMR 7.x EMRFS assembly path
# Find the correct version dynamically
EMRFS_JAR=$(find /usr/share/aws/emr/emrfs/lib/ -name "emrfs-hadoop-assembly-*.jar" 2>/dev/null | head -1)
if [ -z "$EMRFS_JAR" ]; then
    echo "Warning: EMRFS JAR not found, using default path"
    EMRFS_JAR="/usr/share/aws/emr/emrfs/lib/emrfs-hadoop-assembly.jar"
fi

# Hail jar location (if built separately - not needed for wheel-based installation)
HAIL_JAR=$(find /opt -name "hail-all-spark.jar" 2>/dev/null | head -1)
if [ -n "$HAIL_JAR" ]; then
    JAR_PATH="$HAIL_JAR:$EMRFS_JAR"
else
    JAR_PATH="$EMRFS_JAR"
fi

export PYSPARK_SUBMIT_ARGS="--conf spark.driver.extraClassPath='$JAR_PATH' --conf spark.executor.extraClassPath='$JAR_PATH' --conf spark.serializer=org.apache.spark.serializer.KryoSerializer --conf spark.kryo.registrator=is.hail.kryo.HailKryoRegistrator pyspark-shell"
echo "PYSPARK_SUBMIT_ARGS: ${PYSPARK_SUBMIT_ARGS}"

# Configure Jupyter Lab
mkdir -p $HOME/.jupyter
cp /opt/hail-on-AWS-spot-instances/src/jupyter_notebook_config.py $HOME/.jupyter/

mkdir -p $HAIL_HOME/notebook/
chmod -R 777 $HAIL_HOME/notebook
cd $HAIL_HOME/notebook/

# Kill an existing Jupyter Lab if any running
if [ -f /tmp/jupyter_notebook.pid ]; then
    JUPYTERPID=$(cat /tmp/jupyter_notebook.pid)
    kill $JUPYTERPID 2>/dev/null || true
fi

# Start Jupyter Lab using python3.11 on port 8192
nohup /usr/bin/python3.11 -m jupyterlab --port 8192 --ip 0.0.0.0 --no-browser --ServerApp.token='' >/tmp/jupyter_notebook.log 2>&1 &
echo $! > /tmp/jupyter_notebook.pid
echo "Started Jupyter Lab in the background."
echo "Access at: http://<master-ip>:8192"
echo "No password required (token authentication disabled)"
