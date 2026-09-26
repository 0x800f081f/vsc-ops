# Aufgabe 3/4: Terraform, Provider-Versionen und Provider-Konfiguration.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    # Aufgabe 4: Rechte in der Managed PostgreSQL vergeben (GRANT)
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.25"
    }
    # Aufgabe 4: DB-Zugangsdaten als Kubernetes-Secret in den Cluster schreiben
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# Token nur aus der Umgebung ($env:TF_VAR_do_token), nie aus einer Datei.
provider "digitalocean" {
  token = var.do_token
}

# Verbindet sich als Admin (doadmin) mit der Managed DB, um Rechte zu vergeben.
# Host/User/Passwort kommen direkt aus der DB-Ressource - nichts davon steht im Code.
provider "postgresql" {
  host      = digitalocean_database_cluster.postgres.host
  port      = digitalocean_database_cluster.postgres.port
  database  = digitalocean_database_cluster.postgres.database
  username  = digitalocean_database_cluster.postgres.user
  password  = digitalocean_database_cluster.postgres.password
  sslmode   = "require"
  superuser = false # Managed PostgreSQL gibt keinen Superuser heraus
}

# Zugriff auf den Cluster ueber die Daten des importierten Clusters (Aufgabe 3).
provider "kubernetes" {
  host                   = digitalocean_kubernetes_cluster.teko_doks.endpoint
  token                  = digitalocean_kubernetes_cluster.teko_doks.kube_config[0].token
  cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.teko_doks.kube_config[0].cluster_ca_certificate)
}
