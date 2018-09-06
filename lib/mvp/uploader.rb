require 'json'
require 'tty-spinner'
require "google/cloud/bigquery"

class Mvp
  class Uploader
    def initialize(options = {})
      @cachedir = options[:cachedir]
      @mirrors  = options[:gcloud][:mirrors]
      @bigquery = Google::Cloud::Bigquery.new(
        :project_id  => options[:gcloud][:project],
        :credentials => Google::Cloud::Bigquery::Credentials.new(options[:gcloud][:keyfile]),
      )
      @dataset = @bigquery.dataset(options[:gcloud][:dataset])

      raise "\nThere is a problem with the gCloud configuration: \n #{JSON.pretty_generate(options)}" if @dataset.nil?
    end

    def truncate(entity)
      begin
        case entity
        when :authors
          @dataset.table('forge_authors').delete rescue nil
          @dataset.create_table('forge_authors') do |table|
            table.name        = 'Forge Authors'
            table.description = 'A list of all authors (users) on the Forge'
            table.schema do |s|
              s.integer   "module_count",  mode: :required
              s.integer   "release_count", mode: :required
              s.timestamp "created_at",    mode: :required
              s.string    "display_name",  mode: :required
              s.string    "username",      mode: :required
              s.timestamp "updated_at",    mode: :required
              s.string    "gravatar_id",   mode: :required
              s.string    "slug",          mode: :required
              s.string    "uri",           mode: :required
            end
          end

        when :modules
          # both modules and validations
          @dataset.table('forge_modules').delete rescue nil
          @dataset.create_table('forge_modules') do |table|
            table.name        = 'Forge Modules'
            table.description = 'All modules and their metadata on the Forge'
            table.schema do |s|
              s.string    "name",             mode: :required
              s.string    "owner",            mode: :required
              s.string    "version",          mode: :required
              s.string    "slug",             mode: :required
              s.string    "uri",              mode: :required
              s.timestamp "created_at",       mode: :required
              s.timestamp "updated_at",       mode: :required
              s.string    "tasks",            mode: :repeated
              s.string    "homepage_url"
              s.string    "project_page"
              s.string    "issues_url"
              s.string    "source"
              s.boolean   "supported"
              s.string    "endorsement"
              s.string    "module_group"
              s.boolean   "pdk"
              s.string    "operatingsystem",  mode: :repeated
              s.integer   "release_count",    mode: :required
              s.integer   "downloads",        mode: :required
              s.integer   "feedback_score"
              s.integer   "validation_score"
              s.string    "releases",         mode: :repeated
              s.string    "puppet_range"
              s.boolean   "puppet_2x"
              s.boolean   "puppet_3x"
              s.boolean   "puppet_4x"
              s.boolean   "puppet_5x"
              s.boolean   "puppet_6x"
              s.string    "superseded_by"
              s.string    "deprecated_for"
              s.timestamp "deprecated_at"
              s.timestamp "deleted_at"
              s.string    "dependencies",     mode: :repeated
              s.string    "license"
              s.string    "metadata",         mode: :required
            end
          end

          @dataset.table('forge_validations').delete rescue nil
          @dataset.create_table('forge_validations') do |table|
            table.name        = 'Forge Module Validations'
            table.description = 'Validation scores for all the modules on the Forge'
            table.schema do |s|
              s.integer "total"
              s.integer "parser"
              s.integer "metadata"
              s.integer "lint"
              s.string  "name",     mode: :required
            end
          end

        when :releases
          @dataset.table('forge_releases').delete rescue nil
          @dataset.create_table('forge_releases') do |table|
            table.name        = 'Forge Releases'
            table.description = 'Releases of all modules on the Forge'
            table.schema do |s|
              s.string    "name",             mode: :required
              s.string    "owner",            mode: :required
              s.string    "version",          mode: :required
              s.string    "slug",             mode: :required
              s.string    "uri",              mode: :required
              s.timestamp "created_at",       mode: :required
              s.timestamp "updated_at",       mode: :required
              s.timestamp "deleted_at"
              s.string    "deleted_for"
              s.string    "tasks",            mode: :repeated
              s.string    "project_page"
              s.string    "issues_url"
              s.string    "source"
              s.boolean   "supported"
              s.boolean   "pdk"
              s.string    "tags",             mode: :repeated
              s.string    "operatingsystem",  mode: :repeated
              s.integer   "downloads",        mode: :required
              s.integer   "feedback_score"
              s.integer   "validation_score"
              s.string    "puppet_range"
              s.boolean   "puppet_2x"
              s.boolean   "puppet_3x"
              s.boolean   "puppet_4x"
              s.boolean   "puppet_5x"
              s.boolean   "puppet_6x"
              s.string    "dependencies",     mode: :repeated
              s.string    "file_uri",         mode: :required
              s.string    "file_md5",         mode: :required
              s.integer   "file_size",        mode: :required
              s.string    "changelog"
              s.string    "reference"
              s.string    "readme"
              s.string    "license"
              s.string    "metadata",         mode: :required
            end
          end

          sleep 5 # this allows BigQuery time to flush schema changes
        end
      rescue => e
        $logger.error e.message
        $logger.debug e.backtrace.join("\n")
        @channels = @dataset.table('slack_channels')
      end
    end

    def authors()
      upload('authors')
    end

    def modules()
      upload('modules')
    end

    def releases()
      upload('releases')
    end

    def validations()
      upload('validations')
    end

    def github_mirrors()
      @mirrors.each do |entity|
        begin
          spinner = TTY::Spinner.new("[:spinner] :title")
          spinner.update(title: "Mirroring #{entity[:type]} #{entity[:name]} to BigQuery...")
          spinner.auto_spin

          case entity[:type]
          when :view
            @dataset.table(entity[:name]).delete rescue nil # delete if exists
            @dataset.create_view(entity[:name], entity[:query],
                                  :legacy_sql => true)

          when :table
            job = @dataset.query_job(entity[:query],
                                  :legacy_sql => true,
                                  :write      => 'truncate',
                                  :table      => @dataset.table(entity[:name], :skip_lookup => true))
            job.wait_until_done!

          else
            $logger.error "Unknown mirror type: #{entity[:type]}"
          end

          spinner.success('(OK)')
        rescue => e
          spinner.error("(Google Cloud error: #{e.message})")
          $logger.error e.backtrace.join("\n")
        end
      end
    end

    def insert(entity, data)
      table    = @dataset.table("forge_#{entity}")
      response = table.insert(data)

      unless response.success?
        errors = {}
        response.insert_errors.each do |err|
          errors[err.row['slug']] = err.errors
        end
        $logger.error JSON.pretty_generate(errors)
      end
    end

    def upload(entity)
      begin
        spinner = TTY::Spinner.new("[:spinner] :title")
        spinner.update(title: "Uploading #{entity} to BigQuery ...")
        spinner.auto_spin

        @dataset.load("forge_#{entity}", "#{@cachedir}/nld_#{entity}.json",
                        :write      => 'truncate',
                        :autodetect => true)

#         table = @dataset.table("forge_#{entity}")
#         File.readlines("#{@cachedir}/nld_#{entity}.json").each do |line|
#           data = JSON.parse(line)
#
#           begin
#             table.insert data
#           rescue
#             require 'pry'
#             binding.pry
#           end
#         end


        spinner.success('(OK)')
      rescue => e
        spinner.error("(Google Cloud error: #{e.message})")
        $logger.error e.backtrace.join("\n")
      end
    end

    def test()
      require 'pry'
      binding.pry
    end
  end
end
