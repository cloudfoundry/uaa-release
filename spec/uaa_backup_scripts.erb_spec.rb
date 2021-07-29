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
      'properties' => {
        'uaa' => {
          'limitedFunctionality' => {
            'statusFile' => '/var/vcap/data/uaa/bbr_limited_mode.lock'
          },
          'url' => 'http://uaa.test.uaa.url'
        },
      }
    }
  }

  let(:generated_script) {
    binding = Bosh::Template::EvaluationContext.new(properties, nil).get_binding
    ERB.new(File.read(script)).result(binding)
  }

  describe 'pre-backup-lock.erb' do
    let(:script) { "#{__dir__}/../jobs/uaa/templates/bbr/pre-backup-lock.sh.erb" }

    it 'it has all the expected lines' do
      expect(generated_script).to include("touch '/var/vcap/data/uaa/bbr_limited_mode.lock'")
      expect(generated_script).to include('enable_limited_functionality')
      expect(generated_script).to include('sleep 6')
    end
  end

  describe 'pre-restore-lock.erb' do
    let(:script) { "#{__dir__}/../jobs/uaa/templates/bbr/pre-restore-lock.sh.erb" }

    it 'it has all the expected lines' do
      expect(generated_script).to include('/var/vcap/bosh/bin/monit stop uaa')
      expect(generated_script).to include('wait_for_uaa_to_stop')
    end
  end

  describe 'post-backup-unlock.erb' do
    let(:script) { "#{__dir__}/../jobs/uaa/templates/bbr/post-backup-unlock.sh.erb" }

    it 'it has all the expected lines' do
      expect(generated_script).to include("rm -f '/var/vcap/data/uaa/bbr_limited_mode.lock'")
      expect(generated_script).to include('disable_limited_functionality')
      expect(generated_script).to include('sleep 6')
    end
  end
end
