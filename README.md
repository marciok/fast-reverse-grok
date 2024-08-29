# 🔷 Fast Reverse Grok

## Create Your Own Proxy Tunnel Service

Using [FRPS](), [Terraform](), and other tools, I’ll show you how to easily set up your own proxy tunnel on Google Cloud (or AWS).

### What is a Reverse Proxy?

Simply put, a reverse proxy routes traffic from a server to a client, whereas, in a typical proxy setup, your traffic goes from the client to the server.

### How Can This Be Useful?

When you want to expose a service running on a port on your local machine to the web, like when you are developing or testing and need to receive a webhook from an online service, or when you want to show your progress to the rest of the team. It’s also useful if you need to run services on a local machine where you don’t have access to the NAT network.

### Why Create My Own If There Are Already Services That Do This?

I used ngrok for more than 5 years, but they started charging for their service. What was once a useful tool in my toolkit became another expense in my SaaS budget. Because of that, I began searching for free solutions, and it occurred to me that by setting up a VM in the cloud, using a proxy, and tearing it down when done, I could almost eliminate my costs. Plus, I would have access to premium features for free, like a custom domain with HTTPS.

### The Technical Part

#### Server

As previously mentioned, in a proxy setup, we need a server that accepts connections from a client. Therefore, we need to deploy a virtual machine with a public IP where our server will run and accept connections from both clients and the outside world.

We are going to use Google Cloud as the cloud provider. However, if you want to see this tutorial for AWS, please click [here](#).

#### Google Cloud

1. Create a project on Google Cloud and enable the Virtual Machine API.
2. Install and configure the `gcloud` command line tool.
3. Install Terraform.
4. Clone this repo, navigate to the `/server` folder, and run `terraform init`.

Next, we need to create a new VM (Virtual Machine) that accepts connections on the specified ports and runs our server application. The advantage of using Terraform is that we can specify all our resources and connections in a single file and tear them down when we are done using them.

Inside the `/server` folder there's a file named `main.tf` with our VM and network configuration for Google Cloud:

```terraform
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
```

## Set Up Our VM

As mentioned, we are going to set up our infrastructure by executing the `main.tf` script:

```bash
$ terraform apply
# It will ask for your proxy name and the port you wish to expose.
```

The script will take a minute or two to perform and at the end if it worked you should see your public IP address, ex:
```bash

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

instance_public_ip = "35.555.555.88"

```

Congrats! Now we can move to the client.

#### Client

For this part, we are also going to install FRP in the `/client` folder and interact with the client application (`frpc`, with the letter `c` to identify it as the client app).

1. Download FRP.
2. Extract its contents to the `/client` folder.
3. Edit `frpc.toml` to set our public IP and the port that we just specified.

```bash
# frpc.toml
serverAddr = "35.555.555.88"  # Our recently deployed server address
serverPort = 7000             # Port that is open for communication

[[proxies]]
name = "tutorial"     # Naming our proxy
type = "tcp"          # Specifying its type
localIP = "127.0.0.1" # Equivalent to localhost
localPort = 3000      # Local port where the traffic is going to be available
remotePort = 3000     # Public port where the traffic is going to be available
```

4. Run `frpc` to connect with our recently deployed server:
```bash
$ cd client
$ ./frps -c frpc.toml
```

5.	Start the application you want to run, for example:
```bash
$ python3 -m http.server 3000 # Sample python server
```

Finally, your local machine is exposed through FRPS at the port we set up, which means if you access http://35.555.555.88:3000 from anywhere, the request redirects to your application!

**Warning: You are exposing your local machine to the internet, which can be dangerous, so use it cautiously.**

If you are done and don't need to set up an HTTPS endpoint, you can safely stop your client and destroy the VM:

```bash
$ terraform destroy
```

## Enabling HTTPS on your server


Most services today won’t allow you to connect without HTTPS, but don’t worry—FRPS and Certbot have you covered. Just ensure you have a domain that we can use to route our traffic.

1. Point the server's public IP address to your domain by creating an A type record, e.g.:

    ```bash
    Name  Type  Value
    dev     A    35.555.555.88
    ```


2. Connect to your server using SSH so we can download Certbot, generate certificates, and obtain them.
    1. Connect via SSH and run:

    ```bash
    # In our server terminal...
    $ sudo apt install certbot
    ```

    After the installation is completed, run the following:

    ```bash
    sudo certbot certonly --standalone
    ```

    You will be prompted to enter your email and specify the domain that we set in Step 1,

    e.g., `dev.mycustomdomain.com`

    Certbot generated a certificate and key. Copy them so we can use them on our client.

    3. Copy the contents of `fullchain.pem` and paste them into a new file in `/client` as `server.crt`:

    ```bash
    sudo cat /etc/letsencrypt/live/dev.mycustomdomain.com/fullchain.pem
    # Copy the entire content, e.g., --- BEGIN ---- ....
    ```

    4. Copy the contents of `privkey.pem` and paste them into a new file in `/client` as `server.key`:

    ```bash
    sudo cat /etc/letsencrypt/live/dev.mycustomdomain.com/privkey.pem
    ```

    5. Stop your FRPS server so we can set a virtual host and enable HTTPS:

    ```bash
    $ sudo pkill frps
    $ sudo vi /frp/frps.toml
    ```

    6. Edit `frps.toml` to add the `vhost https` port and save:

    ```bash
    # frps.toml
    bindPort = 7000
    VhostHTTPSPort = 443 # <- Add this..
    ```

3. Run FRPS again:

    ```bash
    $ cd /frp
    $ sudo ./frps -c frps.toml &
    ```

4. Now on your local machine, edit `frpsc.toml` to include our domain, certificate, and key copied in Step 2:

    ```bash
    serverAddr = "35.555.555.88"
    serverPort = 7000

    [[proxies]]
    name = "test_https2http"
    type = "https"
    customDomains = ["dev.mycustomdomain.com"]

    [proxies.plugin]
    type = "https2http"
    localAddr = "127.0.0.1:3000"
    crtPath = "./server.crt"
    keyPath = "./server.key"
    ```

Yahoo! We now have HTTPS for our local server! For example:

https://dev.mycustomdomain.com

Congrats! You made it to the end! If you wish to have this all bundled into a single command, click [here](#).
