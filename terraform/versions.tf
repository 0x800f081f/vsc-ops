# Aufgabe 3: Terraform- und Provider-Versionen + DigitalOcean-Provider.
terraform {
  # import-Bloecke mit Variablen in der ID gibt es ab Terraform 1.6
  required_version = ">= 1.6.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Der API-Token kommt NICHT aus dem Repo, sondern aus der Umgebungsvariable
# TF_VAR_do_token (siehe variables.tf / README).
provider "digitalocean" {
  token = var.do_token
}
