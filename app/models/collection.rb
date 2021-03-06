require 'csv'

class Collection < ActiveRecord::Base
  include CollectionStatistic
  extend FriendlyId
  friendly_id :slug_candidates, :use => [:slugged, :history]

  has_many :works, -> { order 'title' }, :dependent => :destroy #, :order => :position
  has_many :notes, -> { order 'created_at DESC' }, :dependent => :destroy
  has_many :articles, :dependent => :destroy
  has_many :document_sets, -> { order 'title' }, :dependent => :destroy
  has_many :categories, -> { order 'title' }
  has_many :deeds, -> { order 'created_at DESC' }, :dependent => :destroy
  has_one :sc_collection, :dependent => :destroy

  belongs_to :owner, :class_name => 'User', :foreign_key => 'owner_user_id'
  has_and_belongs_to_many :owners, :class_name => 'User', :join_table => :collection_owners
  has_and_belongs_to_many :collaborators, :class_name => 'User', :join_table => :collection_collaborators
  attr_accessible :title, :intro_block, :footer_block, :picture, :subjects_disabled, :transcription_conventions, :slug, :review_workflow, :hide_completed, :help, :link_help
#  attr_accessor :picture

  validates :title, presence: true, length: { minimum: 3, maximum: 255 }
  
  before_create :set_transcription_conventions
  before_create :set_help
  before_create :set_link_help
  after_save :create_categories
  after_create :insert_semantic_register
  after_update :update_semantic_register

  mount_uploader :picture, PictureUploader

  scope :order_by_recent_activity, -> { joins(:deeds).order('deeds.created_at DESC') }
  scope :unrestricted, -> { where(restricted: false)}

  def export_subjects_as_csv
    csv_string = CSV.generate(:force_quotes => true) do |csv|
      csv << %w{ Work_Title Page_Title Page_Position Page_URL Subject Text Category Category Category }
      self.works.each do |work|
        work.pages.includes(:page_article_links, articles: [:categories]).each do |page|
          page_url="http://#{Rails.application.routes.default_url_options[:host]}/display/display_page?page_id=#{page.id}"
          page.page_article_links.each do |link|
            display_text = link.display_text.gsub("<lb/>", ' ').gsub("\n", "")
            article = link.article
            category_array = []
            article.categories.each do |category|
              category_array << category.title
            end
            csv << [work.title, page.title, page.position, page_url, link.article.title, display_text, category_array.sort].flatten
          end
        end
      end
    end
    csv_string
  end

  def show_to?(user)
    (!self.restricted && self.works.present?) || (user && user.like_owner?(self)) || (user && user.collaborator?(self))
  end

  def create_categories
    #create two default categories
    category1 = Category.new(collection_id: self.id, title: "People")
    category1.save
    category2 = Category.new(collection_id: self.id, title: "Places")
    category2.save
  end

  def slug_candidates
    if self.slug
      [:slug]
    else
      [
        :title,
        [:title, :id]
      ]
    end
  end

  def should_generate_new_friendly_id?
    slug_changed? || super
  end

  def normalize_friendly_id(string)
    super.truncate(240, separator: '-', omission: '').gsub('_', '-')
  end

  def blank_out_collection
    puts "Reset all data in the #{self.title} collection to blank"
    works = Work.where(collection_id: self.id)
    pages = Page.where(work_id: works.ids)

    #delete deeds for pages and articles (not work add deed)
    Deed.where(page_id: pages.ids).destroy_all
    Deed.where(article_id: self.articles.ids).destroy_all
    #delete articles
    Article.where(collection_id: self.id).destroy_all
    #delete categories (aside from the default)
    Category.where(collection_id: self.id).where.not(title: 'People').where.not(title: 'Places').destroy_all
    #delete notes
    Note.where(page_id: pages.ids).destroy_all
    #delete page_article_links
    PageArticleLink.where(page_id: pages.ids).destroy_all
    #update work transcription version
    works.each do |w|
      w.update_columns(transcription_version: 0)
    end
    #for each page, delete page versions, update all attributes, save
    pages.each do |p|
      p.page_versions.destroy_all
      p.update_columns(source_text: nil, base_image:nil, base_width: nil, base_height: nil, shrink_factor: nil, created_on: Time.now, lock_version: 0, xml_text: nil, status: nil, source_translation: nil, xml_translation: nil, translation_status: nil, search_text: "\n\n\n\n")
      p.save!
    end

    #fix user_id for page version (doesn't get set in this type of update)
    PageVersion.where(page_id: pages.ids).each do |v|
      v.user_id = self.owner.id
      v.save!
    end
    puts "#{self.title} collection has been reset"
  end

  def insert_semantic_register
    SemanticHelper.insert(self.to_jsonld)
  end

  def update_semantic_register
    SemanticHelper.update(self.to_jsonld_was, self.to_jsonld)
  end

  def export_as_rdf
    SemanticHelper.export_as_rdf("transcriptor:#{self.slug}")
  end

  def as_json(options={})
    methods = [:isOwner]
    options[:methods] = options[:methods] ? options[:methods] | methods : methods
    super
  end

  def isOwner
    unless User.current_user.nil? || self.owner==nil
      User.current_user.admin || self.owner.id == User.current_user.id || self.owners.exists?(:id => User.current_user.id)
    else
      false
    end
  end
  def isOwnerCollection(user)
    self.owners.exists?(:id => user.id) || self.owner.id == user.id
  end
  
  protected
    def set_transcription_conventions
      unless self.transcription_conventions.present?
        self.transcription_conventions = "<p><b>Transcription Conventions</b>\n<ul><li><i>Spelling: </i>Use original spelling if possible.</li>\n <li><i>Capitalization: </i>Modernize for readability</li>\n<li><i>Punctuation: </i>Add modern periods, but don't add punctuation like commas and apostrophes.</li>\n<li><i>Line Breaks: </i>Hit <code>return</code> once after each line ends.  Two returns indicate a new paragraph, which is usually indentation  following the preceding sentence in the original.  The times at the end of each entry should get their own paragraph, since the software does not support indentation in the transcriptions.</li>\n <li><i>Illegible text: </i>Indicate illegible readings in single square brackets: <code>[Dr?]</code></li>\n <li>A single newline indicates a line-break in the original document, and will not appear as a break in the text in some views or exports. Two newlines indicate a paragraph, and will appear as a paragraph break in all views.</li></ul>"
      end
    end

    def set_help
      unless self.help.present?
        self.help = "<h2> Transcribing</h2>\n<p> Once you sign up for an account, a new Transcribe tab will appear above each page.</p>\n<p> You can create or edit transcriptions by modifying the text entry field and saving. Each modification is stored as a separate version of the page, so that it should be easy to revert to older versions if necessary.</p>\n<p> Registered users can also add notes to pages to comment on difficult words, suggest readings, or discuss the texts.</p>"
      end
    end

    def set_link_help
      unless self.link_help.present?
        self.link_help = "<h2>Linking Subjects</h2>\n<p> To create a link within a transcription, surround the text with double square braces.</p>\n<p> Example: Say that we want to create a subject link for &ldquo;Dr. Owen&rdquo; in the text:</p>\n<code> Dr. Owen and his wife came by for fried chicken today.</code>\n<p> Place <code>[[ and ]]</code> around Dr Owen like this:</p>\n<code>[[Dr. Owen]] and his wife came by for fried chicken today.</code>\n<p> When you save the page, a new subject will be created for &ldquo;Dr. Owen&rdquo;, and the page will be added to its index. You can add an article about Dr. Owen&mdash;perhaps biographical notes or references&mdash;to the subject by clicking on &ldquo;Dr. Owen&rdquo; and clicking the Edit tab.</p>\n<p> To create a subject link with a different name from that used within the text, use double braces with a pipe as follows: <code>[[official name of subject|name used in the text]]</code>. For example:</p>\n<code> [[Dr. Owen]] and [[Dr. Owen's wife|his wife]] came by for fried chicken today.</code>\n<p> This will create a subject for &ldquo;Dr. Owen's wife&rdquo; and link the text &ldquo;his wife&rdquo; to that subject.</p></a>\n<h2> Renaming Subjects</h2>\n<p> In the example above, we don't know Dr. Owen's wife's name, but created a subject for her anyway. If we later discover that her name is &ldquo;Juanita&rdquo;, all we have to do is edit the subject title:</p>\n<ol><li>Click on &ldquo;his wife&rdquo; on the page, or navigate to &ldquo;Dr. Owen's wife&rdquo; on the home page for the project.</li>\n<li>Click the Edit tab.</li>\n<li> Change &ldquo;Dr. Owen's wife&rdquo; to &ldquo;Juanita Owen&rdquo;.</li></ol>\n<p> This will change the links on the pages that mention that subject, so our page is automatically updated:</p>\n    <code>[[Dr. Owen]] and [[Juanita Owen|his wife]] came by for fried chicken today.</code>\n<h2> Combining Subjects</h2>\n<p> Occasionally you may find that two subjects actually refer to the same person. When this happens, rather than painstakingly updating each link, you can use the Combine button at the bottom of the subject page.</p>\n <p> For example, if one page reads:</p>\n<code>[[Dr. Owen]] and [[Juanita Owen|his wife]] came by for [[fried chicken]] today.</code>\n<p> while a different page contains</p>\n<code> Jim bought a [[chicken]] today.</code>\n<p> you can combine &ldquo;chicken&rdquo; with &ldquo;fried chicken&rdquo; by going to the &ldquo;chicken&rdquo; article and reviewing the combination suggestions at the bottom of the screen. Combining &ldquo;fried chicken&rdquo; into &ldquo;chicken&rdquo; will update all links to point to &ldquo;chicken&rdquo; instead, copy any article text from the &ldquo;fried chicken&rdquo; article onto the end of the &ldquo;chicken&rdquo; article, then delete the &ldquo;fried chicken&rdquo; subject.</p>\n<h2> Auto-linking Subjects</h2>\n<p> Whenever text is linked to a subject, that fact can be used by the system to suggest links in new pages. At the bottom of the transcription screen, there is an Autolink button. This will refresh the transcription text with suggested links, which should then be reviewed and may be saved.</p>\n<p> Using our example, the system already knows that &ldquo;Dr. Owen&rdquo; links to &ldquo;Dr. Owen&rdquo; and &ldquo;his wife&rdquo; links to &ldquo;Juanita Owen&rdquo;. If a new page reads:</p>\n<code> We told Dr. Owen about Sam Jones and his wife.</code>\n<p> pressing Autolink will suggest these links:</p>\n<code> We told [[Dr. Owen]] about Sam Jones and [[Juanita Owen|his wife]].</code>\n<p> In this case, the link around &ldquo;Dr. Owen&rdquo; is correct, but we must edit the suggested link that incorrectly links Sam Jones's wife to &ldquo;Juanita Owen&rdquo;. The autolink feature can save a great deal of labor and prevent collaborators from forgetting to link a subject they previously thought was important, but its suggestions still need to be reviewed before the transcription is saved.</p>"
      end
    end

    def to_jsonld
      jsonld_hash = {
        :@context => SemanticHelper.get_prefixes,
        :@id => "transcriptor:#{self.slug}",
        :@type => "transcriptor:Collection",
        :"rdfs:label" => self.title,
        :"rdfs:comment" => self.intro_block ? self.intro_block : "" 
      }.to_json
    end

    def to_jsonld_was
      jsonld_hash = {
        :@context => SemanticHelper.get_prefixes,
        :@id => "transcriptor:#{self.slug_was}",
        :@type => "transcriptor:Collection",
        :"rdfs:label" => self.title_was,
        :"rdfs:comment" => self.intro_block_was ? self.intro_block_was : "" 
      }.to_json
    end

end
