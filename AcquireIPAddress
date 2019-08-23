# Description: выделить ip адрес при провижионинге ВМ
#
require 'rest_client'
require 'json'
require 'nokogiri'

$evm.log(:info, "Starting SOUS ipam Integration")

prov = $evm.root['miq_provision'] || $evm.root['miq_provision_request']|| \
  $evm.root['miq_provision_request_template'] || $evm.root['service_template_provision_task']|| $evm.root['service_template'] || \
  $evm.root['service_template_provision_task']
p $evm.root['vmdb_object_type']

vm_name = prov.get_option(:vm_name).to_s.strip
p vm_name

prefix_noc_url = prov.get_option(:dialog_networks_list).split('|').first # ссылка на NOC находится до разделителя |
p prefix_noc_url
vnic_profile_id = prov.get_option(:dialog_networks_list).split('|').last # vnic_profile_id находится после разделителя |
p vnic_profile_id
ip_addr = prov.get_option(:dialog_ipaddress_list)                      

vm = $evm.root['miq_provision'].vm #destination
vm_id = $evm.root['miq_provision'].vm.uid_ems 
p vm_id

# Connect to NOC
server = $evm.object['url_sous'] 
username = $evm.object['user_sous'] 
password = $evm.object.decrypt('password_sous') 
@connection = "#{username}:#{password}@#{server}"

# Connect to RHV
server_rhv = $evm.object['url_api_rhv'] 
username_rhv = $evm.object['user_rhv'] 
password_rhv = $evm.object.decrypt('password_rhv')
@connection_rhv = "#{username_rhv}:#{password_rhv}@#{server_rhv}"

# Токен авторизации
auth_token = Base64.strict_encode64("vicloud@internal:#{password_rhv}")

def takeAddressSOUS(ip,vm_name,vm_id,prefix_noc_url)
  $evm.log(:info, "NOC Entering takeAddress")
  begin
  url = 'https://' + @connection + '/ip/ipam/' + prefix_noc_url + '/add_address/'
  p url
  dooie = RestClient.post url, {address: ip, state: 1, fqdn: "#{vm_name}.#{vm_id}", _save: 'Save'}
  puts "Reserved IP #{ip}"
  rescue => e
  		e.response
  end
end

def addNICtoVM(ip,vm_name,vm_id,auth_token,vnic_profile_id)
  $evm.log(:info, "add NIC to RHV VM")
  url = 'https://' + @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics'
  request = RestClient::Request.new(
       method: :post,
       url: url, 
       :headers => {:content_type=> :xml, :accept=> :xml, :authorization => "Basic #{auth_token}" },
       :payload => "<nic><name>nic2</name><interface>virtio</interface><vnic_profile id='#{vnic_profile_id}'/></nic>",
       verify_ssl: false        
      ) 
  p request
  rest_result = request.execute
  
  # Получим id созданного nic<N>
  url_vm_nic = 'https://' + @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics'
  p url_vm_nic
  get_nic_list = RestClient::Resource.new(url_vm_nic,  :verify_ssl =>  false).get
  doc = Nokogiri::XML(get_nic_list)
  data = doc.search('nic').map do |group|
	  [
 		   group['id'],
 		   group.at('name').text,
	  ]
	end
  next_nic_id = {}
  data.each { |k,v| if v == 'nic2';  next_nic_id[0] = k end }
 
  # Добавить выбранный ip адрес в network_filter_parameters
  url = 'https://' + @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics/' + next_nic_id[0] + '/networkfilterparameters'
  request = RestClient::Request.new(
       method: :post,
       url: url, 
       :headers => {:content_type=> :xml, :accept=> :xml, :authorization => "Basic #{auth_token}" },
       :payload => "<network_filter_parameter><name>IP</name><value>#{ip}</value></network_filter_parameter>",
       verify_ssl: false        
      ) 
  p request
  rest_result = request.execute
     
  $evm.log(:info, "create network completed successfully")
end

#Reserve the IP address in sous

puts "Using #{ip_addr} to provision the VM"
takeAddressSOUS(ip_addr,vm_name,vm_id,prefix_noc_url)
sleep(3.minutes)
addNICtoVM(ip_addr,vm_name,vm_id,auth_token,vnic_profile_id)

prov.set_option(:ip_addr, ip_addr)
#prov.set_option(:subnet_addr, subnet_addr)
#prov.set_option(:subnet_mask, subnet_mask)
#prov.set_option(:gateway, gateway)
#prov.set_option(:dns_domain, dns_domain)
