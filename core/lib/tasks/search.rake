namespace :workarea do
  namespace :search_index do
    def setup
      require 'sidekiq/testing/inline' unless ENV['INLINE'] == 'false'
      Workarea.config.bulk_index_batch_size = ENV['BATCH_SIZE'].to_i if ENV['BATCH_SIZE'].present?
    end

    desc 'Reindex all data'
    task all: :environment do
      Rake::Task['workarea:search_index:storefront'].invoke
      Rake::Task['workarea:search_index:admin'].invoke
      Rake::Task['workarea:search_index:help'].invoke
    end

    desc 'Reindex admin'
    task admin: :environment do
      setup
      puts 'Indexing admin...'
      Workarea::Search::Admin.reset_indexes!

      Mongoid.models.each do |klass|
        next unless Workarea::Search::Admin.for(klass.first).present?

        klass.all.each_slice_of(Workarea.config.bulk_index_batch_size) do |models|
          Workarea::BulkIndexAdmin.perform_by_models(models)
        end
      end

      Workarea.config.jump_to_navigation.to_a.each do |tuple|
        Workarea::Search::Admin::Navigation.new(tuple).save
      end
    end

    desc 'Reindex storefront'
    task storefront: :environment do
      setup
      puts 'Indexing storefront...'

      Workarea::Search::Storefront.reset_indexes!
      Workarea::Search::Storefront.ensure_dynamic_mappings

      # This code finds all unique filters for products so we can index a sample
      # product for each to ensure the dynamic mappings get created.
      #
      # This is necessary to fix mapping errors from Elasticsearch when trying
      # to index category percolations against fields which have no mapping.
      #
      map = %{
        function() {
          for (var key in this.filters.#{I18n.locale}) {
            emit(key, null);
          }
        }
      }
      reduce = 'function(key) { return null; }'
      results = Workarea::Catalog::Product.map_reduce(map, reduce).out(inline: 1)
      unique_filters = results.map { |r| r['_id'] }

      sample_products = unique_filters.reduce([]) do |memo, filter|
        filter = "filters.#{I18n.locale}.#{filter}"
        memo << Workarea::Catalog::Product.exists(filter => true).sample
      end

      sample_products.each do |product|
        Workarea::Search::Storefront::Product.new(product).save
      end

      Workarea::Catalog::Category.all.each_by(Workarea.config.bulk_index_batch_size) do |category|
        Workarea::Search::Storefront::CategoryQuery.new(category).create
        Workarea::Search::Storefront::Category.new(category).save
      end

      Workarea::Content::Page.all.each_by(Workarea.config.bulk_index_batch_size) do |page|
        Workarea::Search::Storefront::Page.new(page).save
      end

      Workarea::BulkIndexProducts.perform
      Workarea::BulkIndexSearches.perform
    end

    desc 'Reindex help'
    task help: :environment do
      setup
      puts 'Indexing help...'

      Workarea::Search::Help.reset_indexes!

      Workarea::Help::Article.all.each_by(Workarea.config.bulk_index_batch_size) do |help_article|
        Workarea::Search::Help.new(help_article).save
      end
    end
  end
end
