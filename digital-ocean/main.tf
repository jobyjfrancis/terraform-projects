data "digitalocean_project" "devops" {
  name = "devops"
}

# Create a new Web Droplet in the nyc2 region
resource "digitalocean_droplet" "web" {
  image     = "ubuntu-24-04-x64"
  name      = "jenkins-server"
  region    = "syd1"
  size      = "s-2vcpu-4gb"
  backups   = false
  ssh_keys  = [50340717]
  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    snap install docker
    sleep 20
    docker run -d -p 8080:8080 --name jenkins -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts
  EOF
}

resource "digitalocean_project_resources" "devops_project_resources" {
  project = data.digitalocean_project.devops.id
  resources = [
    digitalocean_droplet.web.urn
  ]
}

resource "digitalocean_firewall" "jenkins_firewall" {
  name = "jenkins-firewall"

  droplet_ids = [digitalocean_droplet.web.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "8080"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
