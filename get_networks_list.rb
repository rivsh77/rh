#
# Description: Выводит Список доступных сетей (сетевых профилей) 
#

require 'rest_client'
require 'json'
require 'nokogiri'

$evm.log(:info, "get_networks_list started")
p $evm.root['vmdb_object_type'] # "vm"

# Скрыть список , если выбрано удаление
case $evm.root['vmdb_object_type']
  when 'vm'
	if $evm.root['dialog_action_list'] ==  'delete network'
  		disp = false  
	else  disp = true
    end
  when 'service_template'     
    disp = true  
end

server = $evm.object['url_api_rhv'] 
username = $evm.object['user_rhv'] 
password = $evm.object.decrypt('password_rhv') 
@connection = "#{username}:#{password}@#{server}"

case $evm.root['vmdb_object_type']
  when 'vm'
	vm = $evm.root['vm']
	vm_id = vm.uid_ems
	nic_id = $evm.root['dialog_nic_list'] 
end

network_list = Hash.new

if $evm.root['vmdb_object_type'] == 'vm'
if nic_id.nil?
	network_list['!'] = '-- select from list --'
else
# Сначала найдем текущий сетевой профиль, чтобы вывести его первым в списке
	url_vm_nic_id = @connection + '/ovirt-engine/api/vms/' + vm_id + '/nics/' + nic_id
	p url_vm_nic_id
	get_vnicprofile_url = RestClient::Resource.new(url_vm_nic_id,  :verify_ssl =>  false).get
	doc = Nokogiri::XML(get_vnicprofile_url)
	root = doc.root
	vm_nic = root.xpath("//vnic_profile/@href")
	vm_nic_link = vm_nic.map { |node| node.children.text  } 

	url_vnic_profile = @connection + vm_nic_link[0].to_s
	get_vnicprofile = RestClient::Resource.new(url_vnic_profile,  :verify_ssl =>  false).get
	doc = Nokogiri::XML(get_vnicprofile)
	root = doc.root
	vm_vnic_profile = root.xpath("//name") 
  	vm_vnic_id = root.xpath("//vnic_profile/@id") 
	vm_network_url = root.xpath("//network/@href")
#vm_nic.map { |node| node.children.text  } 
	vnic_profile_list = vm_vnic_profile.map { |node| node.children.text  }
  	vnic_vnic_id_arr = vm_vnic_id.map { |node| node.children.text  }
	vm_network_url_arr = vm_network_url.map { |node| node.children.text  }

	url_get_network = @connection + vm_network_url_arr[0].to_s
	get_network = RestClient::Resource.new(url_get_network,  :verify_ssl =>  false).get
	doc = Nokogiri::XML(get_network)
	root = doc.root
	network_name = root.xpath("//name")
	network_name_arr = network_name.map { |node| node.children.text  }
	# сохраним извлеченный url тега description на NOC
	network_description = root.xpath("//description")
	network_description_arr = network_description.map { |node| node.children.text  }

	network_list = {network_description_arr[0].to_s + '|' + vnic_vnic_id_arr[0].to_s => vnic_profile_list[0].to_s + '/' + network_name_arr[0].to_s }
end
end  
# Выводим список всех доступных профилей
unless $evm.root['dialog_action_list'] ==  'delete network' # не заходим в этот блок, если выбрано удаление
  case $evm.root['vmdb_object_type']
    when 'vm'
    	cluster_name = vm.v_parent_blue_folder_display_path
    	p vm.v_parent_blue_folder_display_path
    when  'service_template'
    	cluster_name = 'CC1_TEST'
	end 
    p cluster_name
   	url_cluster_network = @connection + '/ovirt-engine/api/networks?search=cluster_network=' + cluster_name + '&follow=vnic_profiles'
    p url_cluster_network
	get_cluster_network = RestClient::Resource.new(url_cluster_network,  :verify_ssl =>  false).get
	doc = Nokogiri::XML(get_cluster_network)
#	root = doc.root
  doc.css("network").each do |network|
    network_name = network.at_css('name').try(:text)
    network_description = network.at_css('description').try(:text)
    vnic_profiles = network.css("vnic_profiles")
    vnic_profile_name = nil
    vnic_profile_id = nil
   	vnic_profiles.each do |vnic_profile| 
      vnic_profile_id = vnic_profile.at('./vnic_profile/@id')
  	  vnic_profile_name = vnic_profile.at_css('name').try(:text)
    end
    if (vnic_profile_name) && (vnic_profile_name.start_with?("vicloud"))
      network_list[network_description + '|' + vnic_profile_id] = vnic_profile_name + '/' + network_name  
      p network_list  #[1/4/192.168.130.128/28 | 1e32008e-9b5b-47dc-a0b2-b43ca2aac80d] = vicloud_1Gbit/vm0701
    end
  end   

end
list_values = {
#    'sort_by'   => :description, #сортировка убрана, чтобы первым в списке шел текущий сетевой профиль
    'data_type' => :string,
    'visible' => disp,
    'required' => false,
    'protected' => false,
    'values' => network_list,
}
list_values.each { |key, value| $evm.object[key] = value }

exit MIQ_OK
