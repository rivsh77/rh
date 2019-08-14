#
# Description: Список существующих сетевых интерфейсов у ВМ
#

require 'rest_client'
require 'json'
require 'nokogiri'

$evm.log(:info, "get_current_nic started")
if $evm.root['dialog_action_list'] ==  'create network'
  disp = false  #Не отображать список
else  disp = true
end

server = $evm.object['url_api_rhv'] 
username = $evm.object['user_rhv'] 
password = $evm.object.decrypt('password_rhv') 
@connection = "#{username}:#{password}@#{server}"
url = @connection + '/ovirt-engine/api/vms/'

vm = $evm.root['vm']
vm_name = vm.name 
vm_id = vm.uid_ems

url_vm_nic = 'https://' + @connection + '/ovirt-engine/api/vms/' + vm_id + '/nics'
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
data.each { |k,v| nic_list[k] = v }
p nic_list   

list_values = {
    'sort_by'   => :description,
    'visible' => disp,
    'data_type' => :string,
    'required' => false,
    'protected' => false,
    'values' => nic_list,
}
list_values.each { |key, value| $evm.object[key] = value }

exit MIQ_OK
