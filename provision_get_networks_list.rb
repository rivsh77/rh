#
# Description: Выводит Список доступных сетей (сетевых профилей) 
#

require 'rest_client'
require 'json'
require 'nokogiri'

$evm.log(:info, "get_networks_list started")

p $evm.root['vmdb_object_type'] # 'service_template'

server = $evm.object['url_api_rhv'] 
username = $evm.object['user_rhv'] 
password = $evm.object.decrypt('password_rhv') 
@connection = "#{username}:#{password}@#{server}"

network_list = Hash.new

# Выводим список всех доступных профилей
    cluster_name = 'CC1_TEST'
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

list_values = {
#    'sort_by'   => :description, #сортировка убрана, чтобы первым в списке шел текущий сетевой профиль
    'data_type' => :string,
    'visible' => true,
    'required' => false,
    'protected' => false,
    'values' => network_list,
}
list_values.each { |key, value| $evm.object[key] = value }

exit MIQ_OK
