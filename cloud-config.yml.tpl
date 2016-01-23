#cloud-config

hostname: ${hostname}

write_files:
  - path: /etc/systemd/system/update-engine.service.d/proxy.conf
    content: |
      [Service]
      Environment=HTTPS_PROXY=http://proxy.example.com:1234

coreos:
  etcd2:
    discovery: ${discovery_url}
    discovery-proxy: http://proxy.example.com:1234
    advertise-client-urls: http://$private_ipv4:2379,http://$private_ipv4:4001
    initial-advertise-peer-urls: http://$private_ipv4:2380
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    listen-peer-urls: http://$private_ipv4:2380
  units :
    - name: etcd2.service
      command: start
    - name: docker-tcp.socket
      command: start
      enable: true
      content: |
        [Unit]
        Description=Docker Socket for the API

        [Socket]
        ListenStream=2375
        BindIPv6Only=both
        Service=docker.service

        [Install]
        WantedBy=sockets.target
    - name: docker.service
      drop-ins:
        - name: 20-http-proxy.conf
          content: |
            [Service]
            Environment="HTTP_PROXY=http://proxy.example.com:1234"
            Environment="NO_PROXY=localhost,127.0.0.1"
      command: restart
    - name: docker.service
      drop-ins:
        - name: 30-custom.conf
          content: |
            [Service]
            Environment="DOCKER_OPTS=--cluster-advertise eth0:2375 --cluster-store etcd://$private_ipv4:2379"
    - name: update-engine.service
      command: restart
    - name: swarm-agent.service
      command: start
      content: |
        [Unit]
        Description=Docker Swarm Agent Container
        After=docker.service
        Requires=docker.service

        [Service]
        TimeoutStartSec=0
        Restart=always
        ExecStartPre=-/usr/bin/docker stop swarm-agent
        ExecStartPre=-/usr/bin/docker rm -f swarm-agent
        ExecStartPre=-/usr/bin/docker pull swarm
        ExecStart=/usr/bin/docker run --name=swarm-agent swarm join --addr=$private_ipv4:2375 etcd://$private_ipv4:2379/nodes

        [Install]
        WantedBy=multi-user.target
    - name: swarm-manager.service
      command: start
      content: |
        [Unit]
        Description=Docker Swarm Manager Container
        After=docker.service
        Requires=docker.service

        [Service]
        TimeoutStartSec=0
        Restart=always
        ExecStartPre=-/usr/bin/docker stop swarm-manager
        ExecStartPre=-/usr/bin/docker rm -f swarm-manager
        ExecStartPre=-/usr/bin/docker pull swarm
        ExecStart=/usr/bin/docker run -p $private_ipv4:4000:4000 --name=swarm-manager swarm manage -H :4000 --replication --advertise $private_ipv4:4000 etcd://$private_ipv4:2379/nodes

        [Install]
        WantedBy=multi-user.target 
    - name: cadvisor.service
      command: start
      content: |
        [Unit]
        Description=cAdvisor Container
        After=docker.service
        Requires=docker.service

        [Service]
        TimeoutStartSec=0
        Restart=always
        ExecStartPre=-/usr/bin/docker stop cadvisor
        ExecStartPre=-/usr/bin/docker rm -f cadvisor
        ExecStartPre=-/usr/bin/docker pull google/cadvisor
        ExecStart=docker run --volume=/:/rootfs:ro --volume=/var/run:/var/run:rw --volume=/sys:/sys:ro --volume=/var/lib/docker/:/var/lib/docker:ro --publish=8080:8080 --detach=true --name=cadvisor google/cadvisor

        [Install]
        WantedBy=multi-user.target 
  update:
    reboot-strategy: off
    group: beta
