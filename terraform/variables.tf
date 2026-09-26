# Aufgabe 3: Wiederverwendbare Konfigurationswerte als Variablen.
# Nicht-geheime Werte stehen in terraform.tfvars, der Token nur in der Umgebung.

variable "do_token" {
  description = "DigitalOcean API-Token. NIE ins Repo - per $env:TF_VAR_do_token setzen."
  type        = string
  sensitive   = true
}

variable "cluster_id" {
  description = "UUID des bestehenden DOKS-Clusters (fuer den import-Block). Aendert sich bei jedem Neuaufbau."
  type        = string
}

variable "cluster_name" {
  description = "Name des Kubernetes-Clusters"
  type        = string
  default     = "teko-doks"
}

variable "region" {
  description = "DigitalOcean-Region"
  type        = string
  default     = "fra1"
}

variable "k8s_version" {
  description = "Kubernetes-Version (DOKS-Slug). Muss zum bestehenden Cluster passen, sonst plant Terraform ein Upgrade."
  type        = string
}

variable "node_pool_name" {
  description = "Name des Worker-Node-Pools"
  type        = string
  default     = "worker-pool"
}

variable "node_size" {
  description = "Droplet-Groesse der Worker-Nodes"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "node_count" {
  description = "Anzahl Worker-Nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.node_count >= 1
    error_message = "node_count muss mindestens 1 sein - 0 wuerde alle Worker-Nodes entfernen."
  }
}
