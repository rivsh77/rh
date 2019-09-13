require 'rest_client'
require 'json'
#
# Description: Current VM CloudForms IP - Выводит текущий ip адрес от CloudForms
#
$evm.log(:info, "get_current_ip_address started")
#
# Get the VM object
#
vm = $evm.root['vm']

curr_ip_addr_hash = {}
curr_ip_addr_hash = Hash[vm.ipaddresses.collect { |item| [item, item] } ]
curr_ip_addr_hash.each do |key, value|
    puts key + ' : ' + value
end

list_values = {
    'sort_by'   => :description,
    'data_type' => :string,
    'required'  => false,
    'values'    => curr_ip_addr_hash
}
list_values.each { |key, value| $evm.object[key] = value }
exit MIQ_OK
