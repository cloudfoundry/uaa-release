require 'rspec'
require 'yaml'
require 'json'
require 'bosh/template/evaluation_context'
require 'spec_helper'

describe 'config.json.erb' do

  let(:properties) {
    {
      'links' => {
        'uaa_db' => {
          'instances' => [],
          'properties' => {
            'release_level_backup' => true,
            'uaadb' => {
              'address' => '127.0.0.1',
              'port' => 5432,
              'db_scheme' => 'postgresql',
              'databases' => [{'name' => 'uaa_db_name', 'tag' => 'uaa'}],
              'roles' => [{'name' => 'admin', 'password' => 'example', 'tag' => 'admin'}]
            }
          }
        },
        'uaa_keys' => {
            'instances' => [],
            'properties' => {
                'encryption' => {
                'active_key_label' => 'fake_active_key_label',
                'encryption_keys' => 'fake_encryption_keys'
            }
          }
        }
      },
      'properties' => {
      }
    }
  }

  let(:erb_file) { "#{__dir__}/../jobs/uaa_key_rotator/templates/config.json.erb" }

  let(:rendered_erb) {
    binding = Bosh::Template::EvaluationContext.new(properties, nil).get_binding
    ERB.new(File.read(erb_file)).result(binding)
  }

  context 'when uaadb.tls is missing, even though it has a default value, due to a bug in bosh links' do
    before do
      expect(properties['links']['uaa_db']['properties']['uaadb']).to_not have_key('tls')
    end

    it 'includes databaseTlsEnabled with value true' do
      expect(JSON.parse(rendered_erb)['databaseTlsEnabled']).to eq(true)
    end

    it 'includes databaseSkipSSLValidation with value false' do
      expect(JSON.parse(rendered_erb)['databaseSkipSSLValidation']).to eq(false)
    end
  end

  context 'when uaadb.tls is set to enabled' do
    before do
      properties['links']['uaa_db']['properties']['uaadb']['tls'] = 'enabled'
    end

    it 'includes databaseTlsEnabled with value true' do
      expect(JSON.parse(rendered_erb)['databaseTlsEnabled']).to eq(true)
    end

    it 'includes databaseSkipSSLValidation with value false' do
      expect(JSON.parse(rendered_erb)['databaseSkipSSLValidation']).to eq(false)
    end
  end

  context 'when uaadb.tls is set to enabled_skip_all_validation' do
    before do
      properties['links']['uaa_db']['properties']['uaadb']['tls'] = 'enabled_skip_all_validation'
    end

    it 'includes databaseTlsEnabled with value true' do
      expect(JSON.parse(rendered_erb)['databaseTlsEnabled']).to eq(true)
    end

    it 'includes databaseSkipSSLValidation with value true' do
      expect(JSON.parse(rendered_erb)['databaseSkipSSLValidation']).to eq(true)
    end
  end

  context 'when uaadb.tls is set to enabled_skip_hostname_validation' do
    before do
      properties['links']['uaa_db']['properties']['uaadb']['tls'] = 'enabled_skip_hostname_validation'
    end

    it 'includes databaseTlsEnabled with value true' do
      expect(JSON.parse(rendered_erb)['databaseTlsEnabled']).to eq(true)
    end

    it 'includes databaseSkipSSLValidation with value true' do
      expect(JSON.parse(rendered_erb)['databaseSkipSSLValidation']).to eq(true)
    end
  end

  context 'when uaadb.tls is set to disabled' do
    before do
      properties['links']['uaa_db']['properties']['uaadb']['tls'] = 'disabled'
    end

    it 'includes databaseTlsEnabled with value false' do
      expect(JSON.parse(rendered_erb)['databaseTlsEnabled']).to eq(false)
    end

    it 'includes databaseSkipSSLValidation with value false' do
      expect(JSON.parse(rendered_erb)['databaseSkipSSLValidation']).to eq(false)
    end
  end
end
