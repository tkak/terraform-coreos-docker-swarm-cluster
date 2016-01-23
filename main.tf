provider "openstack" {
    domain_name = "default"
    tenant_name = "tenant-1"
    auth_url = "keystone url"
}

variable "servers" {
    default = "test-1,test-2,test-3"
}

resource "null_resource" "discovery_url_template" {
    provisioner "local-exec" {
        command = "curl -s 'https://discovery.etcd.io/new?size=${length(split(",", var.servers))}' > discovery_url"
    }
}

resource "template_file" "discovery_url" {
    template = "discovery_url"
    depends_on = [
        "null_resource.discovery_url_template"
    ]
}

resource "template_file" "cloud-init" {
    count = "${length(split(",", var.servers))}"
    template = "${file("cloud-config.yml.tpl")}"

    vars {
        hostname = "${element(split(",", var.servers), count.index)}"
        discovery_url = "${template_file.discovery_url.rendered}"
    }
}

resource "openstack_compute_instance_v2" "coreos" {
    count = "${length(split(",", var.servers))}"
    name = "${element(split(",", var.servers), count.index)}"
    image_name = "coreos image"
    flavor_name = "flavor-1"
    region = "region-1"
    network {
        name = "network-1"
    }
    key_pair = "core"
    security_groups = ["default"]
    user_data = "${element(template_file.cloud-init.*.rendered, count.index)}"
}
