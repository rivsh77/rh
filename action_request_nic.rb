#
# Description: Реализация действия с сетью из кнопки Action
#
require 'rest_client'
require 'json'
require 'nokogiri'

# Get the dialog values
#
$evm.log(:info, "action_request_nic started")
vm = $evm.root['vm']
vm_name = vm.name 
vm_id = vm.uid_ems
nic_id = $evm.root['dialog_nic_list']

# Connect to RHV
server_rhv = $evm.object['url_api_rhv'] 
username_rhv = $evm.object['user_rhv'] 
password_rhv = $evm.object.decrypt('password_rhv')
@connection_rhv = "#{username_rhv}:#{password_rhv}@#{server_rhv}"

# Токен авторизации
auth_token = Base64.strict_encode64("vicloud@internal:#{password_rhv}")
p auth_token

# Connect to NOC
server = $evm.object['url_sous'] 
username = $evm.object['user_sous'] 
password = $evm.object.decrypt('password_sous') 
@connection = "#{username}:#{password}@#{server}"

prefix_noc_url = $evm.root['dialog_networks_list'].split('|').first # ссылка на NOC находится до разделителя |
vnic_profile_id  = $evm.root['dialog_networks_list'].split('|').last # vnic_profile_id находится после разделителя |
p $evm.root['dialog_action_list']
get_ipaddress = $evm.root['dialog_ipaddress_list']
p get_ipaddress

# Выделим из ссылки на NOC vrf и версию http 
prefix_noc_param = prefix_noc_url.split('/', 3)
vrf_prefix = prefix_noc_param[0]
httpv_prefix = prefix_noc_param[1]

# Получим текущий ip VM
url_vm_ip = 'https://' + @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics/' + nic_id + '/networkfilterparameters'
get_ip_list = RestClient::Resource.new(url_vm_ip,  :verify_ssl =>  false).get
doc = Nokogiri::XML(get_ip_list)
data = doc.search('network_filter_parameter').map do |group|
  [
    group['id'],
    group.at('value').text,
	]
end
nwfilter_id = nil         # Текущий id networkfilterparameters
vm_current_ip = nil           # Текущий ip адрес у ВМ
data.each { |k,v| nwfilter_id = k; vm_current_ip = v }

# Узнаем id ipaddress в NOC
begin
	noc_url_ip_id = 'https://' + @connection + '/ip/address'
	dooie = RestClient.get noc_url_ip_id, params: {address: vm_current_ip}
	json_parse = JSON.parse(dooie.to_str)
	if  json_parse[0]["fqdn"] == "#{vm_name}.#{vm_id}"
  		noc_ip_id = json_parse[0]["id"]
	end
	p noc_ip_id
rescue => e
	$evm.root['ae_result'] = 'error'
end
##################################
# Create New Network             #
##################################
case $evm.root['dialog_action_list']
when 'create network'
  $evm.log(:info, "create network started")
  if (get_ipaddress) 
    # Занять адрес в sous
     url = 'https://' + @connection + '/ip/ipam/' + prefix_noc_url + '/add_address/'
    begin 
     dooie = RestClient.post url, {address: get_ipaddress, state: 1, fqdn: "#{vm_name}.#{vm_id}", _save: 'Save'}
     puts url
    rescue => e
  		e.response
	end
	# Получим все nic, чтобы создать новый
	 url_vm_nic = 'https://' + @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics'
	 p url_vm_nic
	 get_nic_list = RestClient::Resource.new(url_vm_nic,  :verify_ssl =>  false).get
	 doc = Nokogiri::XML(get_nic_list)
	 root = doc.root
	 vm_nic = root.xpath("//nic/name")
	 vm_nic_link = vm_nic.map { |node| node.children.text[/\d+/].to_i  }   
     find_gaps_index = (1..vm_nic_link.last).to_a - vm_nic_link
     if find_gaps_index.empty?
       next_nic_name = 'nic' + (vm_nic_link.max + 1).to_s
      else
       next_nic_name = 'nic' + (find_gaps_index.min).to_s
     end
 
     # Добавить NIC в VM
     url = 'https://' + @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics'
     request = RestClient::Request.new(
       method: :post,
       url: url, 
       :headers => {:content_type=> :xml, :accept=> :xml, :authorization => "Basic #{auth_token}" },
       :payload => "<nic><name>#{next_nic_name}</name><interface>virtio</interface><vnic_profile id='#{vnic_profile_id}'/></nic>",
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
	data.each { |k,v| if v == next_nic_name;  next_nic_id[0] = k end }
 
     # Добавить выбранный ip адрес в network_filter_parameters
     url = 'https://' + @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics/' + next_nic_id[0] + '/networkfilterparameters'
     request = RestClient::Request.new(
       method: :post,
       url: url, 
       :headers => {:content_type=> :xml, :accept=> :xml, :authorization => "Basic #{auth_token}" },
       :payload => "<network_filter_parameter><name>IP</name><value>#{get_ipaddress}</value></network_filter_parameter>",
       verify_ssl: false        
      ) 
	 p request
     rest_result = request.execute
     
     $evm.log(:info, "create network completed successfully")
  else
     $evm.log(:info, "free_ip is nil or current_ip is not nil")
  end
##################################
# Удалить NIC у ВМ               #
##################################
when 'delete network'
    $evm.log(:info, "delete network started")
 # Освободим ip адрес в sous
    if (noc_ip_id.to_s) 
      begin
      	url = 'https://' + @connection + '/ip/address/' + noc_ip_id.to_s
      	dooie = RestClient.delete url 
      	puts url
      	$evm.log(:info, "delete network completed successfully")
      rescue => e
  		e.response
	  end
      
      # Unplug NIC from VM
	  url = 'https://' + @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics/' + nic_id + '/deactivate'
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
	  request = RestClient::Request.new(
 	      method: :delete,
 	      url: url, 
 	      :headers => {:content_type=> :xml, :accept=> :xml, :authorization => "Basic #{auth_token}" },
  	     verify_ssl: false        
   	   ) 
      rest_result = request.execute
      p request
  else
     $evm.log(:info, "noc_ip_id is nil")
  end

##################################
# Изменить NIC у ВМ              #
##################################
when 'change network'
	$evm.log(:info, "change network started")
 if (noc_ip_id.to_s) && (vnic_profile_id) && (get_ipaddress)
# Удалим из NOC старый ip адрес по его id
   begin
	url = 'https://' + @connection + '/ip/address/' + noc_ip_id.to_s
	dooie = RestClient.delete url 
	puts url
       rescue => e
  		e.response
	end
	$evm.log(:info, "delete network completed successfully")

	# Занять новый адрес в sous
	url = 'https://' + @connection + '/ip/ipam/' + prefix_noc_url + '/add_address/'
    begin 
     dooie = RestClient.post url, {address: get_ipaddress, state: 1, fqdn: "#{vm_name}.#{vm_id}", _save: 'Save'}
     puts url
    rescue => e
  		e.response
	end
	$evm.log(:info, "add network to NOC completed successfully")

   # Изменить NIC в VM
     url = 'https://' + @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics/' + nic_id
     request = RestClient::Request.new(
       method: :put,
       url: url, 
       :headers => {:content_type=> :xml, :accept=> :xml, :authorization => "Basic #{auth_token}" },
       :payload => "<nic><vnic_profile id='#{vnic_profile_id}'/></nic>",
       verify_ssl: false        
      ) 
	 rest_result = request.execute
     p request
  # Изменить IP в networkfilterparameter в ВМ
	url = 'https://' + @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics/' + nic_id + '/networkfilterparameters/' + nwfilter_id
     request = RestClient::Request.new(
       method: :put,
       url: url, 
       :headers => {:content_type=> :xml, :accept=> :xml, :authorization => "Basic #{auth_token}" },
       :payload => "<network_filter_parameter><name>IP</name><value>#{get_ipaddress}</value></network_filter_parameter>",
       verify_ssl: false        
      )
	 rest_result = request.execute
     p request
	$evm.log(:info, "change ipaddress completed successfully")
 else  
   $evm.log(:info, "noc_ip_id or vnic_profile_id or ipaddress is nil")
 end
end

exit MIQ_OK
