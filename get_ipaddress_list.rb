#
# Description: Список доступных адресов в сети. 
#			   По умолчанию выбирается текущий адрес сетевого интерфейса.
#
require 'rest_client'
require 'json'
require 'nokogiri'

# Список для вывода ip адресов
ipaddress_list = {}
# Промежуточный список для сбора ip адресов
pre_ipaddress_list = {}
vm_curr_ipaddress_arr = []

$evm.log(:info, "get_free_ip_address_NOC started")

# Скрыть список , если выбрано удаление
if $evm.root['dialog_action_list'] ==  'delete network'
  disp = false  
else 
disp = true

# Определим текущий ip по Networkfilterparameter из RHV
server_rhv = $evm.object['url_api_rhv'] 
username_rhv = $evm.object['user_rhv'] 
password_rhv = $evm.object.decrypt('password_rhv')
@connection_rhv = "#{username_rhv}:#{password_rhv}@#{server_rhv}"

if $evm.root['vmdb_object_type'] == 'vm'
 vm = $evm.root['vm']
 vm_id = vm.uid_ems
 nic_id = $evm.root['dialog_nic_list']
 unless nic_id.nil? || $evm.root['dialog_action_list'] ==  'create network'
	url_vm_networkfilterparam = @connection_rhv + '/ovirt-engine/api/vms/' + vm_id + '/nics/' + nic_id + '/networkfilterparameters'
	get_vm_networkfilterparam = RestClient::Resource.new(url_vm_networkfilterparam,  :verify_ssl =>  false).get
	doc = Nokogiri::XML(get_vm_networkfilterparam)
	root = doc.root
	vm_networkfilterparam = root.xpath("//network_filter_parameter/value")
	vm_curr_ipaddress_arr = vm_networkfilterparam.map { |node| node.children.text  } 
	p vm_curr_ipaddress_arr[0] 
 end
end  

# Обращаемся в NOC за свободными ip в данной сети
server = $evm.object['url_sous']
username = $evm.object['user_sous'] 
password = $evm.object.decrypt('password_sous') 
@connection = "#{username}:#{password}@#{server}"

#Извлекаем префикс из ссылки 
prefix_name_extract = $evm.root['dialog_networks_list'].split('|').first 
prefix_name = prefix_name_extract.split('/', 3) 
p prefix_name
unless (prefix_name.nil? || prefix_name == ["!"])
	vrf = prefix_name[0]
	#Получить prefix_id из NOC
	url = 'https://' + @connection + '/ip/prefix/?__only=description%2Cid%2Cprefix&vrf=' + vrf + '&prefix=' + prefix_name[2]
	dooie = RestClient.get url
	json_parse = JSON.parse(dooie.to_str)
	prefix_id = json_parse[0]["id"]

	#Получить занятые ip в префиксе
	url = 'https://' + @connection + '/ip/address/?__only=address,id'

	dooie = RestClient.get url, params: {prefix: prefix_id} #{prefix: 166114}
	json_parse = JSON.parse(dooie.to_str)
	taken_ip = {}
	json_parse.each do |item|
   		taken_ip[item['id']] = item['address']
   		puts  taken_ip[item['id']]
	end  

	#Определение всех ip префикса
	prefix_noc_url = $evm.root['dialog_networks_list'].split('|').first 
	url = 'https://' + @connection + '/ip/ipam/' + prefix_noc_url #192.168.130.128/28/'
	p url
	dooie = RestClient.get url
	doc = Nokogiri::HTML(dooie)
	js = doc.search('script').text.scan(/SPOT=.+/)  
	b = js.to_s.scan(/\\"([^\"]+)\\"/)

	all_ip_arr = b.collect { |c| c.count() ==  1 ? c[0] : c.gsub!('"', '')  }
	free_ip_arr = all_ip_arr - taken_ip.values

	#Определение свободных ip
	free_ip_hash = {}
	free_ip_hash = Hash[free_ip_arr.collect { |item| [item, item] } ]
	free_ip_hash.each do |key, value|
    	puts key + ' : ' + value
	end

	pre_ipaddress_list = free_ip_hash
  else
	$evm.log(:error, "Can't find from dialog_networks_list")
	exit MIQ_ERROR
end

case $evm.root['vmdb_object_type']
	when 'vm'
		if vm_curr_ipaddress_arr[0].nil?
			ipaddress_list = {'!' => '-- select from list --'}.merge(pre_ipaddress_list)
		else 
  		# В списке сначала выводим текущий адрес из Networkfilterparameter
			ipaddress_list = {vm_curr_ipaddress_arr[0]=> vm_curr_ipaddress_arr[0] }.merge(pre_ipaddress_list)
		end
    when 'service_template'
		ipaddress_list = {'!' => '-- select from list --'}.merge(pre_ipaddress_list) 
end
end

list_values = {
#    'sort_by'   => :value, #сортировка убрана, чтобы первым в списке шел текущий сетевой профиль
    'visible' => disp,
    'data_type' => :string,
    'required' => false,
    'protected' => false,
    'values' => ipaddress_list,
}
list_values.each { |key, value| $evm.object[key] = value }

exit MIQ_OK
