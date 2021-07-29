require 'rspec'
require 'yaml'
require 'bosh/template/evaluation_context'
require 'spec_helper'

describe 'bosh backup and restore script' do
  def read_file(relative_path)
    File.read(File.join(File.dirname(__FILE__), relative_path))
  end

  let(:properties) {
    {
      'links' => {
        'uaa_db' => {
          'instances' => [],
          'properties' => {
            'uaadb' => {
              'address' => '127.0.0.1',
              'port' => 5432,
              'db_scheme' => 'postgresql',
              'databases' => [{'name' => 'uaa_db_name', 'tag' => 'uaa'}],
              'roles' => [{'name' => 'admin', 'password' => 'example', 'tag' => 'admin'}]
            }
          }
        }
      },
      'properties' => {
          'release_level_backup' => true,
          'uaadb' => {
              'address' => '127.0.0.2',
              'port' => 2222,
              'db_scheme' => 'postgres',
              'databases' => [{'name' => 'database-name-from-properties', 'tag' => 'uaa'}],
              'roles' => [{'name' => 'ad2min', 'password' => 'exam2ple', 'tag' => 'admin'}],
              'ca_cert' => '---not a real cert---',
          }
      }
    }
  }

  let(:generated_script) {
    binding = Bosh::Template::EvaluationContext.new(properties, nil).get_binding
    generated_script = ERB.new(File.read(script)).result(binding)
  }

  context 'release_level_backup is true' do

    describe 'backup.sh.erb' do
      let(:script) { "#{__dir__}/../jobs/bbr-uaadb/templates/backup.sh.erb" }

      it 'it has all the expected lines' do
        expect(generated_script).to eq(read_file('bbr-uaadb/expected-fixtures/release_level_backup_true.backup.sh'))
      end
    end

    describe 'restore.sh.erb' do
      let(:script) { "#{__dir__}/../jobs/bbr-uaadb/templates/restore.sh.erb" }

      it 'it has all the expected lines' do
        expect(generated_script).to eq(read_file('bbr-uaadb/expected-fixtures/release_level_backup_true.restore.sh'))
      end
    end

    context 'config.json.erb' do

      describe 'when link is used' do
        let(:script) { "#{__dir__}/../jobs/bbr-uaadb/templates/config.json.erb" }

        it 'it has all the expected lines' do
          expect(generated_script).to eq(read_file('bbr-uaadb/expected-fixtures/using-links.config.json'))
        end
      end

      describe 'when properties are used instead of links' do
        before(:each) do
          properties['links'] = nil
        end

        let(:script) { "#{__dir__}/../jobs/bbr-uaadb/templates/config.json.erb" }

        it 'it has all the expected lines' do
          expect(generated_script).to eq(read_file('bbr-uaadb/expected-fixtures/using-properties.config.json'))
        end
      end

      describe 'when ca_cert is not specified' do
        before(:each) do
          properties['properties']['uaadb']['ca_cert'] = nil
        end

        let(:script) { "#{__dir__}/../jobs/bbr-uaadb/templates/config.json.erb" }

        it 'should not contain tls.cert.ca' do
          expect(generated_script).not_to include('tls')
          expect(generated_script).not_to include('cert')
          expect(generated_script).not_to include('ca')
        end
      end
    end
  end

  context 'release_level_backup is false' do

    before(:each) do
      properties['properties']['release_level_backup'] = false
    end

    describe 'backup.sh.erb' do
      let(:script) { "#{__dir__}/../jobs/bbr-uaadb/templates/backup.sh.erb" }

      it 'does not have the backup command' do
        expect(generated_script).to eq(read_file('bbr-uaadb/expected-fixtures/release_level_backup_false.backup.sh'))
      end
    end

    describe 'restore.sh.erb' do
      let(:script) { "#{__dir__}/../jobs/bbr-uaadb/templates/restore.sh.erb" }

      it 'does not have the restore command' do
        expect(generated_script).to eq(read_file('bbr-uaadb/expected-fixtures/release_level_backup_false.restore.sh'))
      end
    end

    context 'config.json.erb' do

      describe 'when link is used' do
        let(:script) { "#{__dir__}/../jobs/bbr-uaadb/templates/config.json.erb" }

        it 'it has all the expected lines' do
          expect(generated_script).to eq(read_file('bbr-uaadb/expected-fixtures/using-links.config.json'))
        end
      end

      describe 'when properties are used instead of links' do
        before(:each) do
          properties['links'] = nil
        end

        let(:script) { "#{__dir__}/../jobs/bbr-uaadb/templates/config.json.erb" }

        it 'it has all the expected lines' do
          expect(generated_script).to eq(read_file('bbr-uaadb/expected-fixtures/using-properties.config.json'))
        end
      end

      describe 'when ca_cert is not specified' do
        before(:each) do
          properties['properties']['uaadb']['ca_cert'] = nil
        end

        let(:script) { "#{__dir__}/../jobs/bbr-uaadb/templates/config.json.erb" }

        it 'should not contain tls.cert.ca' do
          expect(generated_script).not_to include('tls')
          expect(generated_script).not_to include('cert')
          expect(generated_script).not_to include('ca')
        end
      end
    end

  end

end
