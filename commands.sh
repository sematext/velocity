##########
# prereqs
##########

# install Java
apt-get install openjdk-7-jdk

# install Logstash
wget -qO - https://packages.elasticsearch.org/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb http://packages.elasticsearch.org/logstash/2.0/debian stable main" | sudo tee -a /etc/apt/sources.list
apt-get update
apt-get install logstash

# install rsyslog and the modules we'll use
add-apt-repository ppa:adiscon/v8-stable
apt-get update
apt-get install rsyslog rsyslog-elasticsearch rsyslog-mmnormalize rsyslog-kafka

# install Apache Kafka
wget http://apache.javapipe.com/kafka/0.8.2.2/kafka_2.11-0.8.2.2.tgz

# install Elasticsearch
wget -qO - https://packages.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb http://packages.elastic.co/elasticsearch/2.0/debian stable main" | sudo tee -a /etc/apt/sources.list.d/elasticsearch-1.7.list
apt-get update
apt-get install elasticsearch

# install Kibana
wget https://download.elastic.co/kibana/kibana/kibana-4.2.0-beta2-linux-x64.tar.gz
tar zxf kibana-4.2.0-beta2-linux-x64.tar.gz


###############
# logstash
###############
# base conf
cp apache.conf.direct /etc/logstash/conf.d/apache.conf

# things you may want to tune
vim /etc/default/logstash

# if you want to start from scratch
rm /var/lib/logstash/.sincedb*

service elasticsearch start
curl -XDELETE localhost:9200/_all
service logstash start
# waaait for it
service logstash stop

################
# rsyslog
################
# base conf
cp /etc/rsyslog.conf.direct /etc/rsyslog.conf
# mmnormalize rulebase
vim /etc/rsyslog_apache.rb

# if you want to start from scratch
rm /var/run/imfile-state*
curl -XDELETE localhost:9200/_all

service rsyslog restart
# waaait for it
service rsyslog stop

################
# rsyslog + Kafka + Logstash
################
# if you want to start from scratch
rm /var/run/imfile-state*
curl -XDELETE localhost:9200/_all

# set up Kafka
cd kafka_2.11-0.8.2.2/
bin/zookeeper-server-start.sh config/zookeeper.properties
bin/kafka-server-start.sh config/server.properties

# already created
bin/kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic rsyslog_logstash

# set up rsyslog and Logstash
cp /etc/rsyslog.conf.kafka /etc/rsyslog.conf
cp apache.conf.kafka /etc/logstash/conf.d/apache.conf

# start them
service logstash restart
service rsyslog restart

##############
# Elasticsearch demo
##############

curl -XDELETE localhost:9200/_all

curl -XPUT localhost:9200/logs/apache/1 -d '{
  "verb": "GET",
  "path": "/index.html",
  "bytes": 7
}'

# --> index, type, ID -> Lucene Essentials

curl localhost:9200/logs/_search?pretty -d '{
  "query": {
    "bool": {
      "filter": {
        "query_string": {
          "query": "get"
        }  
      }
    }
  }
}'

curl localhost:9200/logs/_search?pretty -d '{
  "query": {
    "bool": {
      "filter": {
        "query_string": {
          "query": "path:index.html"
        }  
      }
    }
  }
}'

# --> analysis

curl localhost:9200/logs/_search?pretty -d '{
  "query": {
    "bool": {
      "filter": {
        "query_string": {
          "query": "verb:GET"
        }  
      }
    }
  },
  "aggs": {
    "top_verbs": {
      "terms": {
        "field": "verb"
      }
    }
  }
}'

curl localhost:9200/logs/_search?pretty -d '{
  "query": {
    "bool": {
      "filter": {
        "query_string": {
          "query": "verb:GET"
        }  
      }
    }
  },
  "aggs": {
    "top_verbs": {
      "terms": {
        "field": "verb"
      },
      "aggs": {
        "avg_bytes_per_verb": {
          "avg": {
            "field": "bytes"
          }
        }
      }
    }
  }
}'

# -> field data detour

curl -XDELETE localhost:9200/logs/

curl -XPUT localhost:9200/logs -d '{
  "mappings": {
    "apache": {
      "properties": {
        "timestamp": {
          "type": "date",
          "doc_values": true,
          "format": "strict_date_optional_time||epoch_millis||dd/MMM/YYYY:HH:mm:ss Z"
        },
        "clientip": {
          "type": "string",
          "index": "not_analyzed",
          "doc_values": true
        },
        "verb": {
          "type": "string",
          "index": "not_analyzed",
          "doc_values": true
        },
        "request": {
          "type": "string",
          "index": "not_analyzed",
          "doc_values": true
        },
        "response": {
          "type": "short",
          "doc_values": true
        },
        "bytes": {
          "type": "long",
          "doc_values": true
        }
      }
    },
    "_default_": {
      "_all": {
        "enabled": true,
        "norms": {
          "enabled": false
        }
      },
      "properties": {
        "timestamp": {
          "type": "date",
          "doc_values": true,
          "format": "strict_date_optional_time||epoch_millis||dd/MMM/YYYY:HH:mm:ss Z"
        }
      },
      "dynamic_templates": [
        {
          "string_fields": {
            "match": "*",
            "match_mapping_type": "string",
            "mapping": {
              "type": "string",
              "norms": {
                "enabled": false
              },
              "fielddata": {
                "format": "disabled"
              },
              "fields": {
                "raw": {
                  "type": "string",
                  "index": "not_analyzed",
                  "doc_values": true
                }
              }
            }
          }
        },
        {
          "other_fields": {
            "match": "*",
            "match_mapping_type": "*",
            "mapping": {
              "doc_values": true
            }
          }
        }
      ]
    }
  },
  "settings": {
    "refresh_interval": "5s"
  }
}'

# configure heap -> how much is actually used? -> http://sematext.com/spm/

vim /etc/default/elasticsearch

# show shards and replicas for new index

curl localhost:9200/_cat/shards?v

# add node, shards again

bin/elasticsearch --node.name velocity02
curl localhost:9200/_cat/shards?v

# third one's a charm

bin/elasticsearch --node.name velocity02
curl localhost:9200/_cat/shards?v

# shutdown one by one

curl -XPUT localhost:9200/_all/_settings -d '{
  "settings": {
    "index.unassigned.node_left.delayed_timeout": "0"
  }
}'

curl localhost:9200/_cat/shards?v

# show time-based indices

curl -XDELETE localhost:9200/_all
curl -XPUT localhost:9200/logstash_2015-10-12 -d '{
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 0
  }
}'
curl -XPUT localhost:9200/logstash_2015-10-13 -d '{
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 0
  }
}'
curl localhost:9200/logstash*/_search
# or better still, search one by one, like Kibana does

# show templates in this context

curl localhost:9200/_template?pretty

curl -XDELETE localhost:9200/_template/logstash

curl -XPUT localhost:9200/_template/logstash_new -d '{
  "template": "logstash*",
  "order": 10,
  "mappings": {
    "apache": {
      "properties": {
        "timestamp": {
          "type": "date",
          "doc_values": true,
          "format": "strict_date_optional_time||epoch_millis||dd/MMM/YYYY:HH:mm:ss Z"
        },
        "clientip": {
          "type": "string",
          "index": "not_analyzed",
          "doc_values": true
        },
        "verb": {
          "type": "string",
          "index": "not_analyzed",
          "doc_values": true
        },
        "request": {
          "type": "string",
          "index": "not_analyzed",
          "doc_values": true
        },
        "response": {
          "type": "short",
          "doc_values": true
        },
        "bytes": {
          "type": "long",
          "doc_values": true
        }
      }
    },
    "_default_": {
      "_all": {
        "enabled": true,
        "norms": {
          "enabled": false
        }
      },
      "properties": {
        "timestamp": {
          "type": "date",
          "doc_values": true,
          "format": "strict_date_optional_time||epoch_millis||dd/MMM/YYYY:HH:mm:ss Z"
        }
      },
      "dynamic_templates": [
        {
          "string_fields": {
            "match": "*",
            "match_mapping_type": "string",
            "mapping": {
              "type": "string",
              "norms": {
                "enabled": false
              },
              "fielddata": {
                "format": "disabled"
              },
              "fields": {
                "raw": {
                  "type": "string",
                  "index": "not_analyzed",
                  "doc_values": true
                }
              }
            }
          }
        },
        {
          "other_fields": {
            "match": "*",
            "match_mapping_type": "*",
            "mapping": {
              "doc_values": true
            }
          }
        }
      ]
    }
  },
  "settings": {
    "refresh_interval": "5s",
    "number_of_shards": 2,
    "number_of_replicas": 0
  }
}'

# hot&cold tags - start nodes
vim /etc/elasticsearch/elasticsearch.yml
service elasticsearch restart
#hot
bin/elasticsearch --node.tag cold --node.name velocitycold01

# start from scratch
curl -XDELETE localhost:9200/_all

# new template to allocate to hot -> show how it works for a new index

curl -XPUT localhost:9200/_template/logstash_allocation -d '{
  "template": "logstash*",
  "order": 20,
  "settings": {
    "index.routing.allocation.include.tag" : "hot"
  }
}'

curl -XPUT localhost:9200/logstash_2015-10-12

curl localhost:9200/_cat/shards?v

# change settings on the fly

curl -XPUT localhost:9200/logstash_2015-10-12/_settings -d '{
  "index.routing.allocation.exclude.tag" : "hot",
  "index.routing.allocation.include.tag": "cold"
}'

curl localhost:9200/_cat/shards?v
