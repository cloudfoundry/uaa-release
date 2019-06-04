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
          'release_level_backup' => true,
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
    generated_script = ERB.new(File.read(script)).result(binding)
  }

  context 'release_level_backup is true' do
    describe 'pre-backup-lock.erb' do
      let(:script) { "#{__dir__}/../jobs/uaa/templates/bbr/pre-backup-lock.sh.erb" }

      it 'it has all the expected lines' do
        expect(generated_script).to include("touch '/var/vcap/data/uaa/bbr_limited_mode.lock'")
        expect(generated_script).to include('  enable_limited_functionality')
        expect(generated_script).to include('sleep 6')
      end
    end

    describe 'pre-restore-lock.erb' do
      let(:script) { "#{__dir__}/../jobs/uaa/templates/bbr/pre-restore-lock.sh.erb" }

      it 'it has all the expected lines' do
        expect(generated_script).to include('/var/vcap/bosh/bin/monit stop uaa')
        expect(generated_script).to include('sleep 15')
      end
    end

    describe 'post-restore-unlock.erb' do
      let(:script) { "#{__dir__}/../jobs/uaa/templates/bbr/post-restore-unlock.sh.erb" }

      it 'it has all the expected lines' do
        expect(generated_script).to eq(read_file('compare/post-restore-unlock.sh'))
      end
    end

    describe 'post-backup-unlock.erb' do
      let(:script) { "#{__dir__}/../jobs/uaa/templates/bbr/post-backup-unlock.sh.erb" }

      it 'it has all the expected lines' do
        expect(generated_script).to include("rm -f '/var/vcap/data/uaa/bbr_limited_mode.lock'")
        expect(generated_script).to include('  disable_limited_functionality')
        expect(generated_script).to include('sleep 6')
      end
    end
  end


  context 'release_level_backup is false' do

    before(:each) do
      properties['properties']['release_level_backup'] = false
    end

    describe 'pre-backup-lock.erb' do
      let(:script) { "#{__dir__}/../jobs/uaa/templates/bbr/pre-backup-lock.sh.erb" }

      it 'it has all the expected lines' do
        expect(generated_script).not_to include("touch '/var/vcap/data/uaa/bbr_limited_mode.lock'")
        expect(generated_script).not_to include('enable_limited_functionality')
        expect(generated_script).not_to include('sleep 6')
      end
    end

    describe 'pre-restore-lock.erb' do
      let(:script) { "#{__dir__}/../jobs/uaa/templates/bbr/pre-restore-lock.sh.erb" }

      it 'it has all the expected lines' do
        expect(generated_script).not_to include('/var/vcap/bosh/bin/monit stop uaa')
        expect(generated_script).not_to include('sleep 15')
      end
    end

    describe 'post-restore-unlock.erb' do
      let(:script) { "#{__dir__}/../jobs/uaa/templates/bbr/post-restore-unlock.sh.erb" }

      it 'it has all the expected lines' do
        expect(generated_script).not_to include('/var/vcap/bosh/bin/monit start uaa')
        expect(generated_script).not_to include('/var/vcap/jobs/uaa/bin/post-start')
        expect(generated_script).not_to include('sleep 15')
      end
    end

    describe 'post-backup-unlock.erb' do
      let(:script) { "#{__dir__}/../jobs/uaa/templates/bbr/post-backup-unlock.sh.erb" }

      it 'it has all the expected lines' do
        expect(generated_script).not_to include("rm -f '/var/vcap/data/uaa/bbr_limited_mode.lock'")
        expect(generated_script).not_to include('disable_limited_functionality')
        expect(generated_script).not_to include('sleep 6')
      end
    end
  end
end
