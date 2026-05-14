require 'minitest/autorun'
require 'active_support/core_ext/object/blank'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'redmine_tx_heatmap/issue_signature'
require 'redmine_tx_heatmap/title_template_miner'
