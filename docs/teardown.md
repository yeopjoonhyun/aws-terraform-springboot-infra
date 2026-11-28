# ECS·EKS 실습 리소스 정리

| 실습 | 삭제 순서 |
| --- | --- |
| ECS | `terraform/app` → `terraform/data` → RDS 최종 스냅샷과 실습용 ECR 이미지 |
| EKS | Argo CD Application·Ingress와 ALB → `terraform/eks` → `terraform/data` → RDS 최종 스냅샷과 실습용 ECR 이미지 |

매 실습 후에는 `network`, `registry`, `bootstrap`을 유지한다. 개인 프로젝트를 종료할 때는 앱과 DB를 정리한 후 `registry`와 `network`를 삭제할 수 있다. `registry`를 삭제하면 ECR과 GitHub Actions의 AWS 배포 역할도 사라진다. `bootstrap`은 Terraform의 리소스 관리 기록(state)을 담은 S3 버킷이라 정리 대상에서 제외한다.

## 개인 계정과 리전 확인

저장소 루트에서 실행한다. `개인 계정 확인`이 출력된 경우에 다음 절차로 넘어간다. 이 셸에서 아래 명령을 계속 실행한다.

```bash
aws_sydney() { aws --region ap-southeast-2 --no-cli-pager "$@"; }

expected_account=$(sed -nE 's/^[[:space:]]*aws_account_id[[:space:]]*=[[:space:]]*"([0-9]{12})".*/\1/p' terraform/network/terraform.tfvars)
active_account=$(aws_sydney sts get-caller-identity --query Account --output text)
test -n "$expected_account" && test "$active_account" = "$expected_account" && printf '개인 계정 확인\n'
```

## 앱부터 삭제

### ECS

실습을 시작할 때 `terraform/app`에 넘긴 이미지 태그를 `TAG`에 넣고 아래를 실행한다. Terraform이 ECS와 ALB, NAT를 삭제한다.

```bash
terraform -chdir=terraform/app destroy -var "image_tag=${TAG:?실습에 사용한 이미지 태그를 지정하세요}"
```

GitHub Actions가 추가한 ECS 작업 정의 버전이 남을 수 있다. `aws_sydney ecs list-task-definitions --family-prefix aws-tf-springboot-app --status ACTIVE`로 목록을 본다. 이번 실습의 정확한 family와 revision이 확인되면 해당 버전을 `TASK_DEFINITION`에 넣고 `aws_sydney ecs deregister-task-definition --task-definition "$TASK_DEFINITION"`으로 등록 해제한다.

### EKS

`kubectl config current-context`에서 개인 계정의 `aws-tf-springboot-eks` 컨텍스트를 확인한다. 실습에서 별도 kubeconfig를 썼다면 같은 파일을 사용한다. 클러스터 삭제 전에 `kubectl get ingress,service -A`로 외부 로드밸런서를 사용하는 리소스를 확인한다. 노드 EBS 디스크까지 확인하려면 노드가 살아 있을 때 EC2에서 해당 노드의 볼륨 ID를 기록한다.

`k8s/teardown.sh`는 먼저 Argo CD Application을 삭제한다. Argo CD가 앱의 Ingress를 지우면 ALB Controller가 AWS 로드밸런서를 제거한다. 이후 스크립트가 앱 네임스페이스와 해당 ALB가 사라졌는지 확인한다. 별도로 만들었던 외부 Ingress나 LoadBalancer Service도 클러스터 안에서 삭제하고 AWS에서 정리를 확인한다. 로드밸런서가 남았거나 스크립트가 실패하면 클러스터를 삭제하기 전에 원인을 확인한다. [AWS EKS 삭제 전 절차](https://docs.aws.amazon.com/eks/latest/userguide/delete-cluster.html#prerequisite-steps)

```bash
k8s/teardown.sh && terraform -chdir=terraform/eks destroy
```

## RDS와 실습 산출물 삭제

앱 삭제 후 아래 조회로 RDS 삭제 방지 상태를 확인한다. `True`일 때만 비활성화 계획을 검토하고 적용한다. 조회 결과가 비어도 `data`의 state에 서브넷 그룹이나 경보가 남아 있으면 해당 루트를 정리한다.

```bash
aws_sydney rds describe-db-instances --query "DBInstances[?DBInstanceIdentifier=='aws-tf-springboot-mysql'].DeletionProtection" --output text
```

```bash
# 삭제 방지가 켜져 있을 때만 실행
terraform -chdir=terraform/data apply -var deletion_protection=false

# data 루트에 정리할 리소스가 있을 때 실행
terraform -chdir=terraform/data destroy -var deletion_protection=false
```

프로젝트는 DB를 지울 때 `aws-tf-springboot-mysql-final` 스냅샷을 남긴다. 실습 데이터의 보관이 필요 없는 경우, 이번 실행에서 만든 최종 스냅샷이 `available`인지 확인한 뒤 해당 ID만 삭제한다. 자동 백업 보존 여부는 최종 스냅샷과 별개다. [AWS RDS 인스턴스 삭제 절차](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_DeleteInstance.html)

```bash
aws_sydney rds describe-db-snapshots --db-snapshot-identifier aws-tf-springboot-mysql-final --query 'DBSnapshots[0].{DB:DBInstanceIdentifier,Status:Status}' --output table
```

```bash
aws_sydney rds delete-db-snapshot --db-snapshot-identifier aws-tf-springboot-mysql-final
aws_sydney rds wait db-snapshot-deleted --db-snapshot-identifier aws-tf-springboot-mysql-final
```

ECR에서 태그와 푸시 시간을 조회한 다음 이번 실습에만 쓴 이미지 태그를 `TAG`에 넣어 삭제한다. 응답의 `failures`가 빈 배열인지 확인한다. ECR 저장소는 다음 실습에서도 사용한다.

```bash
aws_sydney ecr describe-images --repository-name aws-tf-springboot-app --query 'imageDetails[].{Tags:imageTags,Pushed:imagePushedAt}' --output table
```

```bash
aws_sydney ecr batch-delete-image --repository-name aws-tf-springboot-app --image-ids "imageTag=${TAG:?삭제할 실습 태그를 지정하세요}"
```

## 삭제 결과 확인

Terraform의 `app`, `eks`, `data` 중 실행했던 루트에서 `terraform -chdir=terraform/<루트> state list`를 실행한다. 주소가 남아 있다면 AWS 상태와 대조한다. Terraform이 모르는 리소스도 있으므로 AWS API에서 아래 항목을 별도로 확인한다. 각 조회의 결과는 `0`이어야 한다. 조회가 실패하면 오류를 먼저 확인한다.

```bash
project_vpc=$(terraform -chdir=terraform/network output -raw vpc_id)
aws_sydney eks list-clusters --query "length(clusters[?@=='aws-tf-springboot-eks'])" --output text
aws_sydney ecs list-clusters --query "length(clusterArns[?ends_with(@,'/aws-tf-springboot-cluster')])" --output text
aws_sydney ecs list-task-definitions --family-prefix aws-tf-springboot-app --status ACTIVE --query "length(taskDefinitionArns[?contains(@,'/aws-tf-springboot-app:')])" --output text
aws_sydney ec2 describe-instances --filters "Name=vpc-id,Values=$project_vpc" 'Name=tag:eks:cluster-name,Values=aws-tf-springboot-eks' 'Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped' --query 'length(Reservations[].Instances[])' --output text
aws_sydney ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$project_vpc" 'Name=tag:Project,Values=aws-tf-springboot' 'Name=state,Values=pending,available,deleting,failed' --query 'length(NatGateways)' --output text
aws_sydney ec2 describe-addresses --filters 'Name=tag:Project,Values=aws-tf-springboot' --query 'length(Addresses)' --output text
aws_sydney elbv2 describe-load-balancers --query "length(LoadBalancers[?VpcId=='$project_vpc' && (LoadBalancerName=='aws-tf-springboot-alb' || starts_with(LoadBalancerName,'k8s-saanotes'))])" --output text
aws_sydney elbv2 describe-target-groups --query "length(TargetGroups[?VpcId=='$project_vpc' && (TargetGroupName=='aws-tf-springboot-tg' || starts_with(TargetGroupName,'k8s-saanotes'))])" --output text
aws_sydney rds describe-db-instances --query "length(DBInstances[?starts_with(DBInstanceIdentifier,'aws-tf-springboot')])" --output text
aws_sydney rds describe-db-snapshots --snapshot-type manual --query "length(DBSnapshots[?starts_with(DBSnapshotIdentifier,'aws-tf-springboot')])" --output text
aws_sydney rds describe-db-instance-automated-backups --query "length(DBInstanceAutomatedBackups[?starts_with(DBInstanceIdentifier,'aws-tf-springboot')])" --output text
aws_sydney ecr describe-images --repository-name aws-tf-springboot-app --query 'length(imageDetails)' --output text
aws_sydney logs describe-log-groups --log-group-name-prefix /ecs/aws-tf-springboot-app --query "length(logGroups[?logGroupName=='/ecs/aws-tf-springboot-app'])" --output text
aws_sydney cloudwatch describe-alarms --alarm-names aws-tf-springboot-rds-cpu aws-tf-springboot-alb-5xx aws-tf-springboot-target-latency --query 'length(MetricAlarms)' --output text
```

EBS 볼륨 ID를 기록했다면 `aws_sydney ec2 describe-volumes --filters "Name=volume-id,Values=$VOLUME_IDS"`에서 쉼표로 구분한 해당 ID만 조회한다. `Volumes`가 빈 배열이면 모두 삭제된 것이다. 다른 작업이 ECR에 이미지를 올렸다면 이번 실습에 사용한 태그가 사라졌는지 확인한다.

### EKS 네트워크 인터페이스와 보안 그룹

ENI는 EC2와 AWS 서비스가 VPC에 연결할 때 쓰는 가상 네트워크 카드다. 11월 27일에는 노드가 사라진 뒤에도 ENI 한 개가 남아 EKS 보안 그룹을 사용하고 있었다. 해당 VPC 안에서 아래 두 명령의 목록이 비었는지 확인한다. [당시 정리 기록](10-gitops-monitoring.md#정리)

```bash
aws_sydney ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$project_vpc" 'Name=description,Values=aws-K8S-*' --query 'NetworkInterfaces[].{ID:NetworkInterfaceId,Status:Status,Instance:Attachment.InstanceId,Managed:RequesterManaged,Groups:Groups[].GroupId,Description:Description}' --output json
aws_sydney ec2 describe-security-groups --filters "Name=vpc-id,Values=$project_vpc" 'Name=group-name,Values=eks-cluster-sg-aws-tf-springboot-eks-*' --query 'SecurityGroups[].{ID:GroupId,Name:GroupName}' --output json
```

남은 ENI가 있다면 설명의 노드 ID와 보안 그룹을 대조해 이번 클러스터가 만든 것인지 확인한다. 연결된 ENI는 연결을 소유한 서비스를 확인한다. 서비스 관리 ENI는 직접 분리할 수 없다. 이번 실습에 속하고 이미 분리된 `available` ENI만 정확한 ID로 삭제한다. 그다음 ENI와 다른 보안 그룹 규칙이 더 이상 참조하지 않는 클러스터 보안 그룹을 삭제한다. [AWS 서비스 관리 ENI](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/requester-managed-eni.html)

```bash
aws_sydney ec2 delete-network-interface --network-interface-id "${ENI_ID:?확인한 ENI ID를 지정하세요}"
aws_sydney ec2 delete-security-group --group-id "${CLUSTER_SG_ID:?확인한 클러스터 보안 그룹 ID를 지정하세요}"
```

`DependencyViolation`이 나오면 참조가 남아 있다는 뜻이다. ENI를 다시 조회하고 보안 그룹 규칙에도 참조가 있는지 확인한다. 마지막으로 두 목록을 다시 조회한다.
