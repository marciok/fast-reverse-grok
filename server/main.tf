# Define variables to make it easier to customize the port and name
variable "proxy_name" {
  type = string
}

variable "proxy_port" {
  type = string
}

# Terraform setup
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

# Google Cloud needs a project name, create one using their console
provider "google" {
  project = "reverse-proxy-tutorial"
}

# Defining the VPC (Virtual Private Cloud)
resource "google_compute_network" "vpc_network" {
  name = "reverse-proxy-tutorial-network"
}

# Allowing SSH so we can connect later
resource "google_compute_firewall" "allow-ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  direction     = "INGRESS"
}

# Allowing port 7000 for FRPS to connect to the machine
resource "google_compute_firewall" "allow-port-7000" {
  name    = "allow-port-7000"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["7000"]
  }

  source_ranges = ["0.0.0.0/0"]
  direction     = "INGRESS"
}

# Allowing the port that our client will connect to, e.g., 3000, 4000, etc.
resource "google_compute_firewall" "allow-port-proxy" {
  name    = var.proxy_name # Variable for the proxy name
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = [var.proxy_port] # Variable for the port value
  }

  source_ranges = ["0.0.0.0/0"]
  direction     = "INGRESS"
}

# Allowing HTTP and HTTPS connections
resource "google_compute_firewall" "allow-http-https" {
  name    = "allow-http-https"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  direction     = "INGRESS"
}

# Defining the VM where our server will run
# Since the server app does not need many resources, we are selecting the smallest VM available
resource "google_compute_instance" "smallest_vm" {
  name         = "smallest-vm"
  machine_type = "e2-micro" # Micro instance
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name

    access_config {
      # This block ensures the VM gets an external IP
    }
  }

  # Upon machine start, we want to install FRPS and start it.
  metadata_startup_script = <<-EOT
    #!/bin/bash
    curl -fSL https://github.com/fatedier/frp/releases/download/v0.58.1/frp_0.58.1_linux_amd64.tar.gz -o frp.tar.gz &&
    tar -zxvf frp.tar.gz &&
    rm -rf frp.tar.gz &&
    mv frp_*_linux_amd64 /frp
    /frp/frps &
  EOT

  metadata = {
    allow-port-proxy = "true"
    allow-port-7000  = "true"
  }
}

output "instance_public_ip" {
  value = google_compute_instance.smallest_vm.network_interface[0].access_config[0].nat_ip
}