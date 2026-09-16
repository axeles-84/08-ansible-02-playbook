resource "yandex_vpc_network" "develop" {
  name = var.vpc_name
}

resource "yandex_vpc_subnet" "develop_a" {
  name           = "develop-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.develop.id
  v4_cidr_blocks = ["10.0.1.0/24"]
}

data "template_file" "cloudinit" {
  template = file("${path.module}/cloud-init.yml")
  vars = {
    ssh_public_key = var.ssh_public_key
  }
}

locals {
  vms = {
    clickhouse = {
      name = "clickhouse-01"
      zone = "ru-central1-a"
    }
   
}
}

module "vm" {
  source         = "git::https://github.com/udjin10/yandex_compute_instance.git?ref=1.0.0"
  for_each = local.vms
  env_name       = each.key 
  network_id     = yandex_vpc_network.develop.id
  subnet_zones   = [each.value.zone]
  subnet_ids     = [yandex_vpc_subnet.develop_a.id]
  instance_name  = each.value.name
  instance_count = 1
  image_family   = "centos-7-oslogin"
  public_ip      = true
  metadata = {
    user-data          = data.template_file.cloudinit.rendered
    serial-port-enable = 1
  }
  labels = { 
    owner= "a.sorokin",
    project = "accounting"
     }

}
