data "tls_certificate" "eks" {
    url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
    client_id_list = ["sts.amazonaws.com"]
    thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
    url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_policy" "alb_controller" {
    name = "AWSLoadBalancerControllerIAMPolicy"
    policy = file("${path.module}/iam_policy.json")
}

resource "aws_iam_role" "alb_controller" {
    name = "alb-controller-role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Principal = {
                    Federated = aws_iam_openid_connect_provider.eks.arn
                }
                Action = "sts:AssumeRoleWithWebIdentity"
                Condition = {
                    StringEquals = {
                        "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
                        "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
                    }
                }
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
    role    = aws_iam_role.alb_controller.name
    policy_arn = aws_iam_policy.alb_controller.arn
}