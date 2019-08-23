#
# Description: освобождение ip адреса при удалении ВМ
#
require 'rest_client'
require 'json'
require 'nokogiri'

prov = $evm.root['miq_provision'] || $evm.root['vm'].miq_provision || $evm.root['miq_provision_request'] || $evm.root['miq_provision_request_template']
ipaddr = prov.get_option(:ip_addr)
vm_id = prov.vm.uid_ems 
vm_name = prov.vm.name 
nic_id = 0
puts "Starting method to delete IP #{ipaddr}"

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
p auth_token

# Получить список NIC-ов
begin
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
nic_list = {}
data.each { |k,v| nic_list[v] = k }
p nic_list  
rescue => e
  		$evm.root['ae_result'] = 'error'
end

# Узнаем id ip адреса в NOC
def getIPAddress(vm_id,nic_id)
  begin
	p   nic_id
	url_vm_networkfilterparam = @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics/' + nic_id + '/networkfilterparameters'
	get_vm_networkfilterparam = RestClient::Resource.new(url_vm_networkfilterparam,  :verify_ssl =>  false).get
	doc = Nokogiri::XML(get_vm_networkfilterparam)
	root = doc.root
	vm_networkfilterparam = root.xpath("//network_filter_parameter/value")
	vm_curr_ipaddress_arr = vm_networkfilterparam.map { |node| node.children.text  } 
	p vm_curr_ipaddress_arr[0] # print current ip address
    return vm_curr_ipaddress_arr[0]
  rescue Exception => e
                puts e.inspect
                return false
  end  
end

# Узнаем id ip адреса в NOC
def getAddressId(vm_name,vm_id,ip)
  begin
	$evm.log(:info, "NOC Entering getAddressId")
	noc_url_ip_id = 'https://' + @connection + '/ip/address'
	response = RestClient.get noc_url_ip_id, params: {address: ip}
	json_parse = JSON.parse(response.to_str)
	if  json_parse[0]["fqdn"] == "#{vm_name}.#{vm_id}"
      p json_parse[0]["id"]
      return json_parse[0]["id"]
	else puts "Unable to find IP address #{ip}"
    end
  rescue Exception => e
                puts e.inspect
                return false
  end  
end


def deleteAddress(ip)
  $evm.log(:info, "NOC Entering deleteAddress")
  begin
  url = 'https://' + @connection + '/ip/address/' + ip.to_s # to_s ??
  p url
  response = RestClient.delete url 
  puts "Deleted IP #{ip}"
  rescue => e
  		e.response
  end
end

def deleteNICfromVM(vm_id,nic_id,auth_token)
  begin
	$evm.log(:info, "Unplug NIC from VM")
	url = 'https://' + @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics/' + nic_id + '/deactivate'
  p url
	request = RestClient::Request.new(
	       method: :post,
	       url: url, 
	       :headers => {:content_type=> :xml, :accept=> :xml, :authorization => "Basic #{auth_token}" },
	       :payload => "<action/>",
 	      verify_ssl: false        
   	   ) 
	rest_result = request.execute
	p request
      
	# DELETE NIC from VM
	url = 'https://' + @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics/' + nic_id
    p url
	request = RestClient::Request.new(
 	      method: :delete,
 	      url: url, 
 	      :headers => {:content_type=> :xml, :accept=> :xml, :authorization => "Basic #{auth_token}" },
  	     verify_ssl: false        
   	   ) 
	rest_result = request.execute
	p request
  rescue Exception => e
                puts e.inspect
  end  
end


nic_list.each { |nic_name, nic_id| 
  ipAddress = getIPAddress(vm_id,nic_id)
  p ipAddress
  addressId = getAddressId(vm_name,vm_id,ipAddress)
  deleteAddress(addressId)
  deleteNICfromVM(vm_id,nic_id,auth_token)
}
