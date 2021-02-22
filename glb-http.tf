provider "google" {
  # Update credentials to the correct location, alternatively set   GOOGLE_APPLICATION_CREDENTIALS=/path/to/.ssh/bq-key.json in your shell session and   remove the credentials attribute.
  #   credentials = file("cliu201-sa.json")
  project = "cliu201"
  region  = "us-central1"
  zone    = "us-central1-c"

}

############################
# - using existing external ip
# - using existing vm image
############################

###########################  
# install terraform and run terraform init & terraform apply
# 1. create vm as the game server provide the http service
# 2. create the un-managed instance group and add the vm into the instance group
# 3. create the backend service with the instance group
# 4. create url map and http target proxy
# 5. create global ip
# 6. create forwarding rule
###########################  


data "google_compute_image" "jianquan_image" {
  name  = "centos7-nginx"
  project = "jianquan-test"
}

data "google_compute_global_address" "my_address" {
  name = "game-ip"
}


###########################         01-create vm        ########################### 
resource "google_compute_instance" "gameServer" {
  name         = "nginx-http"
  machine_type = "custom-1-2048"
  zone         = "us-central1-c"

  tags = ["http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.jianquan_image.self_link
    }
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral IP
    }
  }

  hostname = "nginx.cliu201"

  allow_stopping_for_update = "true"

#   metadata = {
#     foo = "bar"
#   }

#   metadata_startup_script = "echo hi > /test.txt"

  service_account {
    scopes = ["cloud-platform"]
  }
}


########################### 02-create unmanaged instance group         ########################### 
resource "google_compute_instance_group" "gameServersGroup" {
  name        = "game-server-group"
  description = "game-server-group by terraform"

  instances = [google_compute_instance.gameServer.self_link]

  named_port {
    name = "http"
    port = "80"
  }

  named_port {
    name = "https"
    port = "443"
  }

  zone = "us-central1-c"
}

########################### 03-create backend service and health check  ########################### 
resource "google_compute_backend_service" "be-gameserver" {
  name          = "be-gameserver"
  health_checks = [google_compute_http_health_check.default.id]

  backend {
      group = google_compute_instance_group.gameServersGroup.id
  }
}

resource "google_compute_backend_service" "be-gameserver2" {
  name          = "be-gameserver2"
  health_checks = [google_compute_http_health_check.default.id]

  backend {
      group = google_compute_instance_group.gameServersGroup.id
  }
}

resource "google_compute_http_health_check" "default" {
  name               = "health-check"
  request_path       = "/"
  check_interval_sec = 5
  timeout_sec        = 5
}

###########################  4. create url map and http target proxy
resource "google_compute_target_http_proxy" "game-target-http-proxy" {
  name    = "tgame-target-http-proxy"
  url_map = google_compute_url_map.game-url-map.id
}

resource "google_compute_url_map" "game-url-map" {
  name            = "game-url-map"
  default_service = google_compute_backend_service.be-gameserver.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.be-gameserver.id

    path_rule {
      paths   = ["/test/*"]
      service = google_compute_backend_service.be-gameserver2.id
    }
  }
}




########################### 5. create global ip ########################### 



########################### 6. create forwarding rule ########################### 
resource "google_compute_global_forwarding_rule" "global-rule" {
  
  name       = "global-rule-game-2"
  target     = google_compute_target_http_proxy.game-target-http-proxy.id
  ip_address = data.google_compute_global_address.my_address.address
  port_range = "80"
}




