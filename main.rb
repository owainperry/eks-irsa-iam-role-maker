#!/usr/bin/env ruby
require "logger"
require "net/http"
require "json"
require "aws-sdk-iam"

class Maker
  def initialize(log)
    @log = log
    api_server = get_env("API_SERVER", "https://kubernetes.default.svc")
    service_account = get_env("SERVICE_ACCOUNT", "/var/run/secrets/kubernetes.io/serviceaccount")
    @policy_folder = get_env("POLICY_FOLDER", "/var/policy")
    @name = get_required_env("NAME")
    @service_account_namespace = get_required_env("SA_NAMESPACE")
    @service_account_name = get_required_env("SA_NAME")
    @iam_role_name_prefix = get_required_env("IAM_ROLE_NAME_PREFIX")
    @iam_role_name = "#{@iam_role_name_prefix}-#{@name}"
    @namespace = File.read(File.join(service_account, "namespace"))
    @token = File.read(File.join(service_account, "token"))
    @ca = File.read(File.join(service_account, "ca.crt"))
    @ca_file = File.join(service_account, "ca.crt")
    @log.info("name: #{@name} service account: #{@service_account_name} service account namespace: #{@service_account_namespace} iam role name : #{@iam_role_name}")
    @cplane_resource_url = "#{api_server}/apis/controlplane.cluster.x-k8s.io/v1beta1/namespaces/#{@namespace}/awsmanagedcontrolplanes/#{@name}-control-plane"
    @iam_client = Aws::IAM::Client.new
  end

  def iam_role_exists()
    begin
      resp = @iam_client.get_role({
        role_name: @iam_role_name,
      })
    rescue Aws::IAM::Errors::NoSuchEntity => e
      @log.debug("IAM role #{@iam_role_name} does not exist")
      return false
    end
    @log.debug("IAM role #{@iam_role_name} exists")
    return true
  end

  def create_iam_role(assume_role_policy_document)
    @iam_client.create_role(role_name: @iam_role_name, assume_role_policy_document: assume_role_policy_document)
    policy_files = Dir[File.join(@policy_folder, "*.json")]
    @log.info("policy files: #{policy_files} count: #{policy_files.length}")
    policy_files.each do |f|
      @log.info("Policy file: #{f}")
      policy_document_json = File.read(f)
      @log.info(policy_document_json)
      policy_name = File.basename(f, ".json")
      @log.info("policy name: #{policy_name}")
      resp = @iam_client.put_role_policy({
        policy_document: policy_document_json,
        policy_name: policy_name,
        role_name: @iam_role_name,
      })
    end
    return @iam_client.get_role(role_name: @iam_role_name).role.arn
  rescue StandardError => e
    @log.error("Error creating role: #{e.message}")
    exit 1
  end

  def get_env(name, default)
    if ENV[name] != nil
      return ENV[name]
    end
    return default
  end

  def get_required_env(name)
    n = get_env(name, "")
    if n == ""
      @log.error("envrionment variable #{name} is not set")
      exit 1
    end
    return n
  end

  def get_trust_policy_template()
    uri = URI.parse(@cplane_resource_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.ca_file = @ca_file
    request = Net::HTTP::Get.new(uri.request_uri)
    request.add_field "Authorization", "Bearer #{@token}"
    response = http.request(request)
    if response.code != "200"
      @log.error("Failed to get trust policy")
      @log.error(response.body)
      exit 1
    end
    doc = JSON.parse(response.body)
    return doc["status"]["oidcProvider"]["trustPolicy"]
  end

  def get_trust_policy()
    template = get_trust_policy_template()
    return template.gsub("${SERVICE_ACCOUNT_NAME}", @service_account_name).gsub("${SERVICE_ACCOUNT_NAMESPACE}", @service_account_namespace)
  end

  def run()
    assume_role_policy_document = get_trust_policy()
    @log.debug(assume_role_policy_document)
    @log.info("creating the role named '#{@iam_role_name}'")
    if iam_role_exists() != true
      role_arn = create_iam_role(assume_role_policy_document)
      if role_arn == "Error"
        @log.error("Could not create role.")
      else
        @log.info("Role created with ARN '#{role_arn}'.")
      end
    end
  end
end

log = Logger.new(STDOUT)
m = Maker.new(log)
m.run()
