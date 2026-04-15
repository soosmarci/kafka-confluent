# User manual

## push config change for one component that is running in doccker

```bash
docker-compose restart control-center
```

## remove it, keeping the volumes

```bash
docker compose down
```

## Eliminate Unnamed Volumes: This will remove anonymous local volumes not used by at least one container
```bash
docker volume prune
```

## stops and removes containers and default networks created by up

the `--volumes` remove ALL volumes (named, unnamed)

```bash
docker compose down --volumes
```

# Schema registry

> API docs:\
 https://docs.confluent.io/platform/current/schema-registry/develop/api.html

## API call to retreive schema information

```Bash
curl -s GET http://schema-registry:8081/schemas
```

# Connector

## install connector plugin manually

````Bash
docker exec -it connect bash -lc \
  "confluent-hub install --no-prompt mongodb/kafka-connect-mongodb:1.10.0"
````

````Bash
docker exec -it connect bash -lc \
  "confluent-hub install --no-prompt debezium/debezium-connector-oracle:2.7.0"
````

## query connector REST queries

````Bash
curl -s http://localhost:8083/connector-plugins
curl -s http://localhost:8083/connectors/
curl -s http://localhost:8083/connectors/todo-mongo-source | jq
curl -s http://localhost:8083/connectors/todo-mongo-source/status | jq
````

## create new connector

````Bash
curl -X POST http://localhost:8083/connectors \
	 -H "Content-Type: application/json" \
	 -d @connectors/todo-mongo-source.json
````

## update config

 1. Use 'jq' to extract the content of the "config" key from your file.
 2. Pipe the extracted JSON directly to 'curl' for the PUT request.

````Bash
cat connectors/todo-mongo-source-simple.json | jq '.config' | \
curl -s -X PUT http://localhost:8083/connectors/todo-mongo-source/config \
	-H "Content-Type: application/json" \
	--data @-
````

````Bash
curl -X POST http://localhost:8083/connectors/todo-mongo-source/tasks/0/restart
````

# Docker exec

generic template

```bash
docker exec <container-name> <path-to-script> <script-arguments>
```

## Kafka-topics

### list topics

```bash
docker exec kafka-broker kafka-topics --list --bootstrap-server localhost:9092
```

### describe topics

```bash
docker exec kafka-broker kafka-topics --describe --topic mongo.todoapp.todos --bootstrap-server localhost:9092
```

### alter topics

```bash
docker exec kafka-broker kafka-topics --alter --topic mongo.todoapp.todos --partitions 2 --bootstrap-server localhost:9092
```

# Errors, fixes

## ERROR-00001 ports are not available

> Error response from daemon: \
    ports are not available: \
    exposing port TCP 0.0.0.0:2181 -> 127.0.0.1:0: listen tcp 0.0.0.0:2181: bind: \
    An attempt was made to access a socket in a way forbiddenen by its access permissions.

### 1. find running service on the port

docker ps

linux(wsl)
netstat -ano | grep :2181

### This will check if any process inside WSL is listening on the port
netstat -tuln | grep 2181

windows
netstat -ano | findstr :2181

Example Output (PID is 1234):

  TCP    0.0.0.0:2181           0.0.0.0:0              LISTENING       1234

### 2A. if it returns value, kill the process

tasklist /svc /fi "PID eq 1234"
taskkill /PID 1234 /F

### 2A if not

Restart Docker Desktop

**if still lingers**

### 3. Check for Windows Excluded Ports (Advanced Diagnosis)
After restarting Docker, if the problem persists, check if Windows has reserved the port (this requires PowerShell run as Administrator):

PowerShell
```
netsh interface ipv4 show excludedportrange protocol=tcp
```

Then do this
run admin powershell
```
netsh winsock reset
```

returns:
>Sucessfully reset the Winsock Catalog.
You must restart the computer in order to complete the reset.

then

```
netsh int ip reset
```

returns
The failure on one of the resetting operations (Resetting , failed. Access is denied.) is usually a minor issue related to a temporary lack of administrative access to a specific, non-critical sub-component, even when running as Administrator. It rarely prevents the overall fix from working.

### restart(reboot) PC

## ERROR-00002 KeeperErrorCode = NodeExists

given already upped but not running containers
when docker compose up -d
then

>[2025-11-11 08:19:45,520] ERROR Exiting Kafka due to fatal exception during startup. (kafka.Kafka$)\
 org.apache.zookeeper.KeeperException$NodeExistsException: KeeperErrorCode = NodeExists\
	at org.apache.zookeeper.KeeperException.create(KeeperException.java:126)\
	at kafka.zk.KafkaZkClient$CheckedEphemeral.getAfterNodeExists(KafkaZkClient.scala:2189)\
	at kafka.zk.KafkaZkClient$CheckedEphemeral.create(KafkaZkClient.scala:2127)\
	at kafka.zk.KafkaZkClient.checkedEphemeralCreate(KafkaZkClient.scala:2094)\
	at kafka.zk.KafkaZkClient.registerBroker(KafkaZkClient.scala:106)\
	at kafka.server.KafkaServer.startup(KafkaServer.scala:365)\
	at kafka.Kafka$.main(Kafka.scala:113)\
	at kafka.Kafka.main(Kafka.scala)\
[2025-11-11 08:19:45,521] INFO [KafkaServer id=1] shutting down (kafka.server.KafkaServer)

1. find ephimeral broker
  - open desktop docker
  - open zookeeper
  - navigate to exec tab
  
```
/bin/zookeeper-shell localhost:2181
```

then

ls /brokers/ids

### 📚 Root Cause Analysis: Stale Ephemeral ZNode

The error occurs when a Kafka broker attempts to register itself with Zookeeper, but a persistent Zookeeper node for that same broker ID already exists.
When a Kafka broker crashes or is killed ungracefully, Zookeeper detects the connection loss but holds onto the broker's ephemeral ZNode (/brokers/ids/\<ID\>) until the session timeout expires.

| Component | Description |
| ----- | ----- |
| **ZNode Path** | `/brokers/ids/<BROKER_ID>` (e.g., `/brokers/ids/1`) |
| **ZNode Type** | **Ephemeral (Temporary)** |
| **Why it gets "stuck"** | The broker was **ungracefully terminated** (crashed or `docker kill`). This prevented the Zookeeper client from closing its session cleanly and deleting the ephemeral registration node. |
| **Conflict** | The new container attempts to create a node at `/brokers/ids/1`, but Zookeeper throws the `NodeExistsException` because the old node is still there. |
| **Self-Resolution** | The stuck node will eventually be cleaned up by Zookeeper when the **session timeout** is reached (usually 18+ seconds), which is why the issue sometimes resolves itself after a wait. |

### 🛠️ Step-by-Step Manual Fix Guide (Targeted Pruning)

This procedure manually deletes the stale ZNode without affecting persistent Kafka topic data volumes.

#### Step 1: Stop the Conflicting Service

Stop the Kafka broker container to prevent it from immediately trying to register or re-creating a session during the fix.

```bash
docker compose stop kafka
```

#### Step 2: Access the Zookeeper Container

Use the Docker Exec command to get a shell inside the running Zookeeper container. (Replace <ZK_CONTAINER_NAME> with your actual Zookeeper container name).

```Bash
docker exec -it <ZK_CONTAINER_NAME> /bin/bash
```

#### Step 3: Run the Zookeeper CLI

Locate and execute the Zookeeper client shell. Since the path often varies, try the common options:

```Bash
# Try this first (most common for ZK images):
/bin/zookeeper-shell localhost:2181
```

- OR:
```
zkCli.sh
```

You should see a message confirming the connection (Welcome to ZooKeeper!).

#### Step 4: Verify and Delete the Stale Node
Once connected, verify the broker ID is present and then delete the conflicting ephemeral ZNode. Use the broker ID from your error log (in the example, it was 1).

List Brokers (Optional Verification):

```
ls /brokers/ids
```
(If you see [1] in the list, the node is stuck.)

Delete the Node (The Fix):

```
delete /brokers/ids/1
```

#### Step 5: Exit and Restart
Quit Zookeeper CLI:

```
quit
```

Exit Container Shell:

```Bash
exit
```

Start Kafka: Run this command from your host machine's terminal. Kafka should now start and register cleanly.

```Bash
docker compose start kafka
```

---

### Suggested Long-Term Solutions for Kafka Stability

#### 1. Robust Startup Dependencies (Preventing Race Conditions) 

🛡️The most reliable fix for Docker Compose is eliminating the race condition where Kafka tries to connect before Zookeeper is fully initialized and ready.

- **Solution**: Use the healthcheck block in your `docker-compose.yml` to ensure Zookeeper is fully operational before Kafka is allowed to start.

| Service | Configuration | Rationale | 
| --- | --- | --- | 
| **Zookeeper** | Define a healthcheck using the Zookeeper ruok (Four Letter Word) command to verify liveness.| Confirms Zookeeper is actively listening and ready to accept connections and process heartbeats. | 
| **Kafka** | Use depends_on: zookeeper: condition: service_healthy. | Guarantees Kafka's main process waits until Zookeeper has passed its health checks, preventing startup during a transient state.
| 

#### 2. Delayed broker startup

implement this in each broker

**Why and how can it help?**\
By delaying the Kafka container's start, you give Zookeeper the necessary grace period to perform the cleanup, ensuring the node is gone before the new broker attempts to register and throws the NodeExists error.

```yml
  volumes:
    # Mount the delay script into the container
    - ./scripts/startup_delay.sh:/tmp/startup_delay.sh 

  # *** THE DELAYED START COMMAND ***
  command: >
    bash -c "chmod +x /tmp/startup_delay.sh && /tmp/startup_delay.sh"
```

#### 3. Tuning Zookeeper Session Timeout 
⏱️If a broker crash occurs, the wait time for the ZNode to clear is determined by the session timeout.
- **Property**: Configure `zookeeper.session.timeout.ms` in Kafka's `server.properties`.
- **Action**: Reduce this value from the default (often 18 000 ms or 45 000 ms) to a lower, stable figure (e.g., 6 000 ms).
- **Trade-off**: A shorter timeout results in faster failover and less wait time after a crash, but it must be longer than the maximum expected network latency or JVM Garbage Collection pause to prevent false "death" reports.

#### 4. Migrate to KRaft (Kafka Raft) 

The ultimate, long-term industry solution is eliminating the Zookeeper dependency entirely.
- **Technology**: Kafka Raft (KRaft), available in Kafka version 3.0+.
- **Benefit**: KRaft allows Kafka to manage its own metadata using the Raft consensus protocol.
- **Result**: By removing Zookeeper, the entire class of Zookeeper-related metadata errors, including `KeeperErrorCode = NodeExists`, is permanently solved.

## ERROR-00003 Replication factor: 2 larger than available brokers: 1.

This is a clear and crucial error from Kafka. We have successfully bypassed the Docker build issues, the Connect plugin issue, and the MongoDB connection issue!

The application is now attempting to create a topic (`mongo.todoapp.todos` or similar) based on the configuration in your `todo-mongo-source.json`, and it is failing with a configuration error:

> Replication factor: 2 larger than available brokers: 1.

**The Problem**

Your Kafka Connect configuration (`todo-mongo-source.json`) explicitly requests that any new topics it creates (specifically for the MongoDB change stream data) must have a replication factor of 2:

```JSON
"topic.creation.default.replication.factor": "2",
```

However, your `docker-compose.yml` only runs a single Kafka broker instance (``kafka-broker``). Kafka cannot replicate a topic across two brokers if only one exists, hence the error.

**The Fix**: Update the Connector Configuration

The quickest and safest fix is to change the replication factor in your connector configuration to 1, which is the correct value for a single-broker development environment.

**Next Steps**

Re-post Connector: Run the curl command again. Since the configuration file name wasn't explicitly provided in the last turn, I'm using the file path ``todo-mongo-source.json`` for consistency.

```Bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/todo-mongo-source-simple.json
```

If the replica set on MongoDB is correctly initialized (which we suspected was the previous error), this command should now succeed, and your Kafka Connect source connector will be running!

