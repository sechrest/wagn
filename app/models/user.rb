require 'digest/sha1'

class User < ActiveRecord::Base
  #FIXME: THIS WHOLE MODEL WILL BE SPLIT INTO User and Account
  # Card::Account will be a new extended cardtype
  # Refactor to warden/devise first
  
  # Declare devise configuration
  devise :all
  
  cattr_accessor :current_user
  
  has_and_belongs_to_many :roles
  belongs_to :invite_sender,     :class_name=>'User',
               :foreign_key=>'invite_sender_id'
  has_many   :invite_recipients, :class_name=>'User',
               :foreign_key=>'invite_sender_id'

  acts_as_card_extension
   
  validates_presence_of     :email,                 :if => :email_required?
  validates_format_of       :email, :with =>
     /^([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})$/i  , :if => :email_required?
  validates_length_of       :email,
                              :within => 3..100,    :if => :email_required?
  validates_uniqueness_of   :email, :scope=>:login, :if => :email_required?  
  validates_presence_of     :password,              :if => :password_required?
  validates_presence_of     :password_confirmation, :if => :password_required?
  validates_length_of       :password,
                              :within => 5..40,     :if => :password_required?
  validates_confirmation_of :password,              :if => :password_required?
  validates_presence_of     :invite_sender,         :if => :active?
#  validates_uniqueness_of   :salt, :allow_nil => true
  
  before_validation :downcase_email!
  
  cattr_accessor :cache, :root_login, :nobody_login, :aliases
  self.aliases = {}
  self.cache = {}
  self.root_login=self.find_by_id(1).login
  logger.info("Login:Root: #{self.cache[:root]}\n")
  self.nobody_login=self.find_by_id(2).login
  logger.info("Login:Nobody: #{self.cache[:nobody]}\n")
#debugger

  class << self
    # CURRENT USER
    Card::Base.login_alias :root, :admin, :wagbot
    Card::Base.login_alias :nobody, :anon, :anonymous
    def current_user; @@current_user ||= self.anonymous end
    def current_user=(user)
raise "User not user #{user.class}" if user && !User===user
logger.info "User not user #{user.class}" if user && !User===user
      @@current_user = user ? User===user ? user : self[user] : anonymous
    end
    def anonymous; self[self.nobody_login] end
    def admin; self[self.root_login] end
   
    def as(as_user=nil)
      unless as_user===User
#b=as_user
        as_user = as_user && self[as_user] || admin
#c = self[b] if b
#d = admin unless b and c
#as_user = b and c or d
#debugger unless User === as_user
raise "User for as not user (#{b}) #{as_user.class}\n#{as_user.inspect}\n" unless User===as_user
      end
      #logger.info("WagnRunAs *#{as_user}*\n")
      tmp_user, self.current_user = self.current_user, as_user
      if block_given?
        value = yield
        self.current_user = tmp_user
        return value
      else
        current_user
      end
    end

    # FIXME: args=params.  should be less coupled..
    def create_with_card(user_args, card_args, email_args={})
      @card = (Hash===card_args ? Card.new({'type'=>'User'}.merge(card_args)) : card_args) 
      @user = User.new({:invite_sender=>User.current_user, :status=>'active'}.merge(user_args))
      # gen_pw = Does devise do the mailing here? need to look into it
      #@user.generate_password if @user.encrypted_password.blank?
      @user.save_with_card(@card)
      #begin
      #  @user.send_account_info(email_args) if @user.errors.empty? && !email_args.empty?
      #end
      [@user, @card]
    end

=begin
def create(*args)
super
rescue Exception=>e
debugger
raise e
end
=end
    def random_base64(n=9)
      ActiveSupport::SecureRandom.base64(n)
    end

    def authenticate?(email, password)
      (u = self.find_by_email(email.strip.downcase)) &&
        self.authenticate({:email => u.email, :password => password.strip}) ? u : nil
    end

    def alias_to_user(login)
      return u if (u=self.aliases[login])===User
      self.aliases[login] = self.cache[login]
    end
    def [](login)
      if (login=login.to_s).blank? ; nil
      else self[login] = alias_to_user(login) || self.find_by_login(login) end
    end
    def active_users; self.find(:all, :conditions=>"status='active'") end 
    def []=(login, user); self.cache[login] = user end
    def no_logins?; self.cache[:no_logins] ||= User.count < 3 end
    def clear_cache; self.cache = {} end
  end 

  ## INSTANCE METHODS
  def save_with_card(card)
    #fail "save with card #{card.inspect}"
    User.transaction do
      save
      card.extension = self
      card.save
      card.errors.each do |key,err|
        next if key=='extension'
        self.errors.add key,err
      end
      raise ActiveRecord::RecordInvalid.new(self) if !self.errors.empty?
    end
  rescue  
  end

  def accept(email_args)
    User.as do #what permissions does approver lack?  Should we check for them?
      card.type = 'User'  # change from Invite Request -> User
      card.permit :edit, Card.new(:type=>'User').who_can(:edit) #give default user permissions
      self.status='active'
      self.invite_sender = ::User.current_user
      email_args[:password] = generate_password
      save_with_card(card)
    end
    #card.save #hack to make it so last editor is current user.
    self.send_account_info(email_args) if self.errors.empty?
  end

  def send_account_info(args)
    #return if args[:no_email]
    raise(Wagn::Oops, "subject is required") unless (args[:subject])
    raise(Wagn::Oops, "message is required") unless (args[:message])
    begin
#Mailer.deliver_account_info(self, args[:subject], args[:message], args[:password])
logger.info("Send acct info #{self}, #{args[:subject]}, #{args[:message]}, #{args[:password]})\n")
    rescue Exception=>e; warn("\nACCOUNT INFO DELIVERY FAILED: #{e.full_message} \n #{args.inspect}")
#debugger
    end
  end  

  def all_roles
    @cached_roles ||= (login=='anon' ? [Role[:anon]] : 
      roles + [Role[:anon], Role[:auth]])
  end  
  def generate_password;
    if encrypted_password.blank?; password = User.random_base64 else '' end
  end
  def active?; status=='active' end
  def blocked?; status=='blocked' end
  def built_in?; status=='system' end
  def pending?; status=='pending' end
  def anonymous?; login == nobody_login end
  def to_s; "#<#{self.class.name}:#{login.blank? ? email : login}}>" end
  def mocha_inspect; to_s end
  def downcase_email!; self.email=self.email.downcase if self.email end 
  # blocked methods for legacy boolean status
  def blocked=(block)
    self.status = if block != '0'; 'blocked'
      elsif !built_in?; 'active'
      else self.status end
  end
   
  protected
  def password_required?
     rs = !built_in? && !pending? && local? &&
      (encrypted_password.blank? or not password.blank?)
  end
  def email_required?; !built_in? end
  def local?; true end # make false for remove service based logins ...
end

