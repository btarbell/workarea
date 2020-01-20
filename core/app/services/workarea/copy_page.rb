module Workarea
  class CopyPage
    def initialize(page, attrs = {})
      @page = page
      @attributes = Workarea.config.page_copy_default_attributes.merge(attrs)
    end

    def perform
      page_copy = @page.clone
      page_copy.assign_attributes(@attributes)
      page_copy.copied_from = @page

      existing_page = Catalog::Page.find(page_copy.id) rescue nil

      if existing_page.present?
        page_copy.errors.add(
          :id,
          I18n.t('workarea.errors.messages.must_be_unique')
        )
      else
        content_clone = @page.content.clone
        content_clone.assign_attributes(contentable_id: page_copy.id)

        content_clone.save!
        page_copy.save!
      end

      page_copy
    end
  end
end
