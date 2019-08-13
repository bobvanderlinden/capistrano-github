require 'capistrano/bundler'
require 'capistrano/plugin'
require 'capistrano/github/api'

class Capistrano::Github::Deployments < Capistrano::Plugin

  def set_defaults
    set_if_empty :github_deployment_payload, -> do
      {

      }
    end

    set_if_empty :github_deployment, -> do
      {
          auto_merge: false,
      }
    end

    set_if_empty :github_deployment_api, -> do
      Capistrano::Github::API.new(fetch(:repo_url), fetch(:github_access_token))
    end

    set :github_deployment_required, false

    set :github_deployment_enabled, -> do
      begin
        fetch(:github_deployment_api)
      rescue Capistrano::Github::API::MissingAccessToken
        false
      end
    end

    set :github_deployment_skip, -> do
      !fetch(:github_deployment_enabled) && !fetch(:github_deployment_required)
    end
  end

  def define_tasks
    desc 'Create new deployment'
    task 'github:deployment:create' do
      next if fetch(:github_deployment_skip)

      gh = fetch(:github_deployment_api)
      payload = fetch(:github_deployment_payload)
      config = fetch(:github_deployment).merge(payload: payload, environment: fetch(:stage))
      branch = fetch(:branch)

      set :current_github_deployment, deployment = gh.create_deployment(branch, config)

      run_locally do
        info("Created GitHub Deployment #{deployment}")
      end
    end

    [:pending, :success, :error, :failure].each do |status|
      desc "Mark current deployment as #{status}"
      task "github:deployment:#{status}" => 'github:deployment:create' do
        next if fetch(:github_deployment_skip)

        gh = fetch(:github_deployment_api)
        deployment = fetch(:current_github_deployment)

        run_locally do
          if deployment
            gh.create_deployment_status(deployment, status)
            info("Marked GitHub Deployment #{deployment} as #{status}")
          else
            info("No GitHub Deployment found, could not mark as #{status}")
          end
        end
      end
    end

    print_deployment = -> d { puts "Deployment (#{d.last_state}): #{d.created_at} #{d.ref}@#{d.sha} to #{d.environment} by @#{d.creator_login}" }
    print_status = -> s { puts "\t#{s.created_at} state: #{s.state}" }

    desc 'List Github deployments'
    task 'github:deployments' do
      gh = fetch(:github_deployment_api)
      env = fetch(:github_deployment)[:environment]
      gh.deployments(environment: env).each do |deployment|
        deployment.tap(&print_deployment)
        deployment.statuses.each(&print_status)
      end
    end

    desc 'Show last Github deploy'
    task 'github:last_deploy' do
      gh = fetch(:github_deployment_api)
      env = fetch(:github_deployment)[:environment]
      gh.deployments(environment: env).first.tap(&print_deployment)
    end
  end

  def register_hooks
    after  'deploy:starting', 'github:deployment:create'
    after  'github:deployment:create', 'github:deployment:pending'
    after  'deploy:finished', 'github:deployment:success'
    after  'deploy:failed',   'github:deployment:failure'
  end

end
