#!/bin/bash
set -euxo pipefail

REGION="${region}"
BASE_DOMAIN="${base_domain}"
CLUSTER_NAME="${cluster_name}"
PULL_SECRET='${pull_secret}'
SSH_KEY='${ssh_pub_key}'

# ---------------------------------------------------------------------------#
# 0. AWS credentials for the installer itself
# ---------------------------------------------------------------------------#
mkdir -p /root/.aws

cat > /root/.aws/credentials <<EOF
[default]
aws_access_key_id=${aws_access_key}
aws_secret_access_key=${aws_secret_key}
EOF

export AWS_ACCESS_KEY_ID=${aws_access_key}
export AWS_SECRET_ACCESS_KEY=${aws_secret_key}
export AWS_REGION=${REGION}            # good practice

#------------------------------------------------------------------------------#
# 1. Tools
#------------------------------------------------------------------------------#
yum update -y
yum install -y wget tar jq
cd /opt

# ── openshift-install ─────────────────────────────────────────────────────────#
wget -q https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-install-linux.tar.gz
tar -xf openshift-install-linux.tar.gz
rm -f  openshift-install-linux.tar.gz        # <— free space immediately
mv openshift-install /usr/local/bin/

# ── oc + kubectl ──────────────────────────────────────────────────────────────#
wget -q https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz
tar -xf openshift-client-linux.tar.gz
rm -f  openshift-client-linux.tar.gz         # <— free space immediately
mv oc kubectl /usr/local/bin/

# ── drop cached RPMs (≈300 MB) ────────────────────────────────────────────────#
yum -y clean all
rm -rf /var/cache/yum
export PATH=$PATH:/usr/local/bin


#------------------------------------------------------------------------------#
# 2. Generate install-config.yaml (non-interactive)
#------------------------------------------------------------------------------#
mkdir -p /root/ocp && cd /root/ocp

cat > install-config.yaml <<EOF
additionalTrustBundlePolicy: Proxyonly
apiVersion: v1
baseDomain: ${BASE_DOMAIN}

metadata:
  name: ${CLUSTER_NAME}

controlPlane:
  name: master
  architecture: amd64
  hyperthreading: Enabled
  replicas: 1           # single master (SNO)
  platform: {}

compute:
- name: worker
  architecture: amd64
  hyperthreading: Enabled
  replicas: 0           # no workers – SNO
  platform: {}

networking:
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16

platform:
  aws:
    region: ${REGION}
    zones:
    - us-east-1a  
    defaultMachinePlatform:
      type: m6i.2xlarge   # ≥ 8 vCPU / 32 GiB for SNO

publish: External
pullSecret: '${PULL_SECRET}'
sshKey: |
  ${SSH_KEY}
EOF


# Longer wait & better AWS retry
export AWS_RETRY_MODE=adaptive
export AWS_MAX_ATTEMPTS=10
export OPENSHIFT_INSTALL_INFRASTRUCTURE_READY_TIMEOUT=40m

#------------------------------------------------------------------------------#
# 3. Kick off the install & stream logs
#------------------------------------------------------------------------------#
openshift-install create cluster --dir . --log-level=info \
  | sudo tee /var/log/openshift-installer.log
