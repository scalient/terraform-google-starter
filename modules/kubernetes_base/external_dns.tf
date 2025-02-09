/**
 * Copyright 2025 Scalient LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

data "google_project" "project" {
  project_id = var.project.project_id
}

// The organization's domain name is stored in the organization-level secrets project.
data "google_secret_manager_secret_version_access" "domain_name" {
  project = local.organization_secrets_project
  secret  = "domain_name"
}

locals {
  // The ExternalDNS service account as it appears to GCP through the principal representing the cluster's Workload
  // Identity pool.
  external_dns_workload_identity_principal = join("",
    [
      "principal://iam.googleapis.com/projects/${data.google_project.project.number}/",
      "locations/global/workloadIdentityPools/",
      "${var.project.cluster.workload_identity_config[0].workload_pool}/subject/",
      "ns/${kubernetes_namespace.external_dns.metadata[0].name}/",
      "sa/${kubernetes_service_account.external_dns.metadata[0].name}",
    ]
  )
  external_dns_version = "v0.15.1"
}

// Following the tutorial here:
// https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/gke.md#deploy-externaldns.

resource "kubernetes_namespace" "external_dns" {
  metadata {
    name = "external-dns"
  }
}

resource "kubernetes_service_account" "external_dns" {
  metadata {
    name      = kubernetes_namespace.external_dns.metadata[0].name
    namespace = kubernetes_namespace.external_dns.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = kubernetes_namespace.external_dns.metadata[0].name
    }
  }
}

resource "kubernetes_cluster_role" "external_dns" {
  metadata {
    name = kubernetes_service_account.external_dns.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = kubernetes_service_account.external_dns.metadata[0].name
    }
  }

  rule {
    api_groups = [""]
    resources = ["services", "endpoints", "pods", "nodes"]
    verbs = ["get", "watch", "list"]
  }

  rule {
    api_groups = ["extensions", "networking.k8s.io"]
    resources = ["ingresses"]
    verbs = ["get", "watch", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "external_dns_service_account_external_dns" {
  metadata {
    name = kubernetes_service_account.external_dns.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = kubernetes_service_account.external_dns.metadata[0].name
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.external_dns.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.external_dns.metadata[0].name
    namespace = kubernetes_namespace.external_dns.metadata[0].name
  }
}

resource "kubernetes_deployment" "external_dns" {
  metadata {
    name      = kubernetes_service_account.external_dns.metadata[0].name
    namespace = kubernetes_namespace.external_dns.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = kubernetes_service_account.external_dns.metadata[0].name
    }
  }

  spec {
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        "app.kubernetes.io/name" = kubernetes_service_account.external_dns.metadata[0].name
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = kubernetes_service_account.external_dns.metadata[0].name
        }
      }

      spec {
        service_account_name = kubernetes_service_account.external_dns.metadata[0].name

        container {
          name  = kubernetes_service_account.external_dns.metadata[0].name
          image = "registry.k8s.io/external-dns/external-dns:${local.external_dns_version}"
          args = [
            "--source", "service",
            "--source", "ingress",
            "--domain-filter", data.google_secret_manager_secret_version_access.domain_name.secret_data,
            "--provider", "google",
            "--log-format", "json",
            "--google-project", local.dns_hub_project,
            "--google-zone-visibility", "public",
            "--policy", "upsert-only",
            "--registry", "txt",
            "--txt-owner-id", "${var.project.project_id}-${var.project.cluster.name}",
          ]
        }
      }
    }
  }
}

resource "google_dns_managed_zone" "_" {
  project     = local.dns_hub_project
  name        = "main"
  dns_name    = "${data.google_secret_manager_secret_version_access.domain_name.secret_data}."
  description = "The main DNS zone"
}

resource "google_project_iam_member" "dns_hub_project_external_dns_workload_identity_principal" {
  project = local.dns_hub_project
  member  = local.external_dns_workload_identity_principal
  role    = "roles/dns.reader"
}

resource "google_dns_managed_zone_iam_member" "dns_hub_dns_managed_zone_external_dns_workload_identity_principal" {
  project      = local.dns_hub_project
  member       = local.external_dns_workload_identity_principal
  managed_zone = google_dns_managed_zone._.name
  role         = "roles/dns.admin"
}
