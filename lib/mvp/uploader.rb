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

    def mirrors()
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
