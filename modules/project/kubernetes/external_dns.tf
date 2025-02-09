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

data "google_container_cluster" "_" {
  project  = var.project.project_id
  name     = var.project.cluster.name
  location = var.project.cluster.location
}

data "google_project" "_" {
  project_id = var.project.project_id
}

locals {
  // Create the federated workload identity principal bound to the `external-dns/external-dns` Kubernetes service
  // account.
  external_dns_workload_identity_principal = join("",
    [
      "principal://iam.googleapis.com/projects/${data.google_project._.number}/",
      "locations/global/workloadIdentityPools/",
      "${data.google_container_cluster._.workload_identity_config[0].workload_pool}/subject/",
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
            // This can't be used yet because the module doesn't have the necessary domain inputs.
            // "--domain-filter", "",
            "--provider", "google",
            "--log-format", "json",
            "--google-project", local.dns_hub_project,
            "--google-zone-visibility", "public",
            "--policy", "upsert-only",
            "--registry", "txt",
            "--txt-owner-id", "${data.google_project._.project_id}-${data.google_container_cluster._.name}",
          ]
        }
      }
    }
  }
}

// Give the cluster's Workload Identity principal access to the DNS hub project.
resource "google_project_iam_member" "external_dns_workload_identity" {
  project = local.dns_hub_project
  member  = local.external_dns_workload_identity_principal
  role    = "roles/dns.admin"
}
