require 'optparse'

@opts = { override: false, region: 'us-west-2', ezid_debug: false, pause_ezid: false }

OptionParser.new do |parser|
  parser.banner = "Usage: ruby initial_setup [options]"
  parser.on("-e", "--environment ENV", "The environment (Example: dev)") { |e| @opts[:env] = e }
  parser.on("-r", "--region AWS_REGION", "The AWS region (Default: us-west-2)") { |r| @opts[:region] = r }
  parser.on("-o", "--override", TrueClass, "Replace existing values") { |o| @opts[:override] = o }

  parser.on("-h", "--hosted-zone ZONE", "The HostedZoneId") { |h| @opts[:hosted_zone] = h }
  parser.on("-a", "--admin-email EMAIL", "The Administrator email address") { |a| @opts[:email] = a }

  parser.on("-x", "--pause-ezid", TrueClass, "Pause EZID submissions") { |o| @opts[:pause_ezid] = o }

  parser.on("-m", "--ezid-debug-mode", TrueClass, "Increase Lambda log output") { |m| @opts[:ezid_debug] = m }
  parser.on("-n", "--ezid-orgname NAME", "Your EZID hosting insitution name") { |n| @opts[:ezid_org] = n }
  parser.on("-s", "--ezid-shoulder SHOULDER", "Your EZID DOI shoulder") { |s| @opts[:ezid_shoulder] = s }
  parser.on("-u", "--ezid-username USER", "Your EZID username") { |u| @opts[:ezid_user] = u }
  parser.on("-p", "--ezid-password PWD", "Your EZID password") { |p| @opts[:ezid_pwd] = p }
  parser.on("-j", "--jwt-secret JWT_SECRET", "The DMPTool JSON Web Token Secret") { |p| @opts[:jwt_secret] = p }
end.parse!

def put_param(key:, val:, secure: false, override: false)
  dmptool_vals = %w[JWTSecret]
  service = dmptool_vals.include?(key) ? 'tool' : 'hub'
  name = "/uc3/dmp/#{service}/#{@opts[:env]}/#{key}"

  args = [
    "--region #{@opts[:region]}",
    "--name #{name}",
    "--value '#{val}'",
    "--type #{secure ? 'SecureString' : 'String'}"
  ]
  args << "--overwrite" if @opts[:override]

  puts "Adding value for SSM parameter #{name} --> '#{key == 'EzidPassword' ? '********' : val}'"
  `aws ssm put-parameter #{args.join(' ')}`
end

if @opts.length > 3 && !@opts[:env].nil?
  puts "Using options:"
  pp @opts
  puts ""

  ezid_doi_base = 'https://doi.org/'
  ezid_url = @opts[:env].downcase == 'prd' ? 'https://ezid.cdlib.org/' : 'https://ezid-stg.cdlib.org/'

  put_param(key: 'HostedZoneId', val: @opts[:hosted_zone]) unless @opts[:hosted_zone].nil?
  put_param(key: 'AdminEmail', val: @opts[:email]) unless @opts[:email].nil?

  put_param(key: 'EzidApiUrl', val: ezid_url)
  put_param(key: 'EzidBaseUrl', val: ezid_doi_base)

  put_param(key: 'EzidDebugMode', val: @opts[:ezid_debug])
  put_param(key: 'EzidPaused', val: @opts[:pause_ezid])

  put_param(key: 'EzidHostingInstitution', val: @opts[:ezid_org]) unless @opts[:ezid_org].nil?
  put_param(key: 'EzidShoulder', val: @opts[:ezid_shoulder], secure: true) unless @opts[:ezid_shoulder].nil?
  put_param(key: 'EzidUsername', val: @opts[:ezid_user], secure: true) unless @opts[:ezid_user].nil?
  put_param(key: 'EzidPassword', val: @opts[:ezid_pwd], secure: true) unless @opts[:ezid_pwd].nil?

  put_param(key: 'JWTSecret', val: @opts[:jwt_secret], secure: true) unless @opts[:jwt_secret].nil?
else
  puts 'You must specify the environment and one or more options! Run `ruby initial_setup -h` for more info.'
end
