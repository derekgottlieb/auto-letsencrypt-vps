require 'pry-byebug'
require 'rubyflare'
require 'json'
require 'pp'
require 'socket'
require 'date'
require 'fileutils'

def direct_a_record?(record_type: , record_content: , local_ips: [])
  record_type == 'A' && local_ips.include?(record_content)
end

def indirect_cname?(record_type: , record_content: , local_hostname: )
  record_type == 'CNAME' && record_content == local_hostname
end

# Get the hostname for this host to compare against CNAME records in Cloudflare
hostname = Socket.gethostbyname(Socket.gethostname).first

# Get the IPv4 addresses for this host to compare against A records in Cloudflare
ip_addresses ||= Socket.ip_address_list.find_all { |ai| ai.ipv4? && !ai.ipv4_loopback? }.map { |ai| ai.ip_address }

CONFIG = YAML.load(File.open(File.expand_path(File.dirname(__FILE__)) + "/config.yml"))

cf = Rubyflare.connect_with(CONFIG['cloudflare']['user_email'], CONFIG['cloudflare']['user_api_key'])

begin
  zones_raw = cf.get('zones')

  zones = {}
  zones_raw.results.map { |z| zones[z[:name]] = z[:id] }
  puts "Found #{zones.size} zones in Cloudflare" if CONFIG['debug']
rescue => e
  puts e.message # error message
end

begin
  domains_hosted_here = zones.map {|zone_name,zone_id|
    recs = cf.get("zones/#{zone_id}/dns_records")

    domains_hosted_here_zone = recs.results.map { |record|
      name = record[:name]
      type = record[:type]
      content = record[:content]
      record_name = nil
      puts "Checking #{name} / #{type}" if CONFIG['debug']
      
      # Make sure we've actually got a web directory for this domain
      if File.directory?('/var/www/' + name) &&
         (direct_a_record?(record_type: type,
                           record_content: content,
                           local_ips: ip_addresses) ||
          indirect_cname?(record_type: type,
                          record_content: content,
                          local_hostname: hostname))
        record_name = name
      end

      record_name
    }.compact!
    
    puts "domains_hosted_here_zone: #{domains_hosted_here_zone}" if CONFIG['debug']
    domains_hosted_here_zone
  }.flatten!
  
  puts "domains_hosted_here: #{domains_hosted_here}" if CONFIG['debug']
rescue => e
  puts e.message
end

if domains_hosted_here.nil?
  puts "OH NO"
  exit 1
end
  

domains_hosted_here.map {|domain|
  skip = false
  cert_dir = "/var/www/#{domain}/ssl"
  cert_file = "#{cert_dir}/cert.pem"
  
  unless File.directory?(cert_dir)
    FileUtils.mkdir_p cert_dir
  end
  
  # If we have an existing certificate, determine if it's expiring within the next month
  if File.exists?(cert_file)
    raw = File.read cert_file # DER- or PEM-encoded
    certificate = OpenSSL::X509::Certificate.new raw
    if Date.today.next_month.to_time < certificate.not_after
      # Existing cert expires in over a month, don't bother to renew yet
      puts "Skipping #{domain} since it has a recent cert" if CONFIG['debug']
      skip = true
    end
  end
  
  unless skip
    puts "Updating cert for #{domain}" if CONFIG['debug']
    system("cd #{cert_dir} && /usr/local/sbin/simp_le --email #{CONFIG['letsencrypt']['email']} -d #{domain}:/tmp/letsencrypt -f key.pem -f cert.pem -f fullchain.pem -f account_key.json")
  end
}
