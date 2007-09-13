 module WagnHelper
  require_dependency 'wiki_content'

  Droplet = Struct.new(:name, :link_options)
  class Slot
    
    attr_reader :card, :context, :action, :renderer
    attr_accessor :form, :editor_count, :options_need_save, :transclusion_mode,
      :transclusions, :position, :renderer, :form
    def initialize(card, context, action, template=nil, renderer=nil )
      @card, @context, @action, @template, @renderer= card, context.to_s, action.to_s, template,renderer
      @position = nested_context? ? context.split(':').last : 0
      @subslots = []  
      @transclusion_mode = 'view'
      @renderer ||= Renderer.new(self)
    end

    def id(area="") 
      area, id = area.to_s, ""
      if nested_context?
        id << context.gsub(/\:.*$/,'')
      else         
        id << (context == 'main' ? 'main-card' : "#{context.gsub(/\:.*$/,'')}") 
        # FIXME this is kindof a crude test-- don't want to add a card id if one is already there
        unless id =~ /\d+/
          id << (card.id ? "-#{card.id}" : '')
        end
      end
      id << (area.blank? ? "" : "-#{area}")
    end
       
    def nested_context?
      context =~ /\:/
    end
     
    def selector
      positions = context.split(':')
      positions.shift # first one is id
      selector = "#" + id
      if positions.empty? 
        selector << " span[cardid=#{card.id}]"
      else
        while pos = positions.shift
          selector << " span[position=#{pos}]"
        end   
      end
      selector
    end

    def editor_id(area="")
      area, eid = area.to_s, ""
      if nested_context?
        eid << context
      else     
        eid << id + (position > 0 ? "-#{position}" : "")
      end
      eid << (area.blank? ? '' : "-#{area}")
    end

    def url_for(url)
      url = "/#{url}" 
      url << "/#{card.id}" if card.id
      url << context_cgi
    end

    def context_cgi
      context=='main' ? '' : "?context=#{context}"
    end

    def method_missing(method_id, *args, &proc)
      @template.send("slot_#{method_id}", self, *args, &proc)
    end 
    
    def render( card, mode=:view, args={} )
      oldmode, @transclusion_mode = @transclusion_mode, mode
      result = @renderer.render( card, args.delete(:content) || "", update_refs=false)
      @transclusion_mode = oldmode
      result
    end

    def subslot(card)
      # Note that at this point the subslot context, and thus id, are
      # somewhat meaningless-- the subslot is only really used for tracking position.
      new_slot = Slot.new(card, id, @action, @template, @renderer)
      @subslots << new_slot 
                                     
      # NOTE this code is largely copied out of rails fields_for
      options = {} # do I need any? #args.last.is_a?(Hash) ? args.pop : {}
      object_name = "cards[#{card.id}]"
      object  = card 
      block = Proc.new {}
      
      builder = options[:builder] || ActionView::Base.default_form_builder
      fields_for = builder.new(object_name, object, @template, options, block)       
      new_slot.form = fields_for
      new_slot.position = @subslots.size
      new_slot
    end
    
    def render_transclusion( card, *args )    
      subslot(card).send("render_transclusion_#{@transclusion_mode}", *args)
    end   
    
    def render_transclusion_view( options={} )
      if card.new_record? 
        %{<span class="faint createOnClick" position="#{position}" cardid="" cardname="#{card.name}">}+
          %{Click to create #{card.name}</span>}
      else
        # FIXME: there is lots of handling of options missing here.
        # FIXME: this render could theoretically pull from the cache.
        content = @renderer.render( card )
        # Because the returned content is wikiContent, we use wrap!
        # to add while keeping the original object
        # WOW this pre_rendered thing is a hack... 
        content.pre_rendered.wrap! %{<span class="editOnDoubleClick" position="#{position}" cardid="#{card.id}">}, "</span>"
        content.pre_rendered.wrap!(%{<span class="transcluded">}, '</span>' ) if options[:shade]=='on'
        content
      end
    end
    
    def render_transclusion_edit( options={} )
      %{<div class="card-slot">} +
        %{<span class="title">#{@template.less_fancy_title(card)}</span> } + 
        content_field( form ) +
        "</div>"
    end
        
    def render_diff(card, *args)
      @renderer.render_diff(card, *args)
    end
    
  end

  
  # For cases where you just need to grab a quick id or so..
  def slot
    Slot.new(@card,@context,@action)
  end

  def slot_for( card, context, action, options={}, &proc )
    options[:render_slot] = !request.xhr? if options[:render_slot].nil?            
    slot = Slot.new(card, context, action, self)
    if options[:render_slot]
      css_class = ''      
      if slot.action=='line'  
        css_class << 'line' 
      else
        css_class << 'paragraph'                     
      end
      css_class << ' full' if (context=='main' or (action!='view' and action!='line'))
      css_class << ' sidebar' if context=='sidebar'
      css_class << " #{options[:class]}" if options[:class]
      slot_head = %{<div id="#{slot.id}" class="card-slot #{css_class}">}
      concat(slot_head, proc.binding)  
      yield slot
      concat(%{</div>}, proc.binding)
    else
      yield slot
    end
  end 
  

  def slot_notice(slot)
    %{<span id="#{slot.id(:notice)}" class="notice">#{controller.notice}</span>}
  end

  def slot_header(slot)
    render :partial=>'card/header', :locals=>{ :card=>slot.card, :slot=>slot }
  end
  
  def slot_menu(slot)
    menu = %{<div class="card-menu">\n}
  	menu << slot.link_to_menu_action('view')
  	if slot.card.ok?(:edit) 
    	menu << slot.link_to_menu_action('edit')
  	else
  	  menu << link_to_remote("Edit", :url=>slot.url_for('card/denied'), :update=>slot.id)
	  end
  	menu << slot.link_to_menu_action('changes')
  	menu << slot.link_to_menu_action('options')
    menu << "</div>"
  end

  def slot_footer(slot)
    render :partial=>"card/footer", :locals=>{ :card=>slot.card, :slot=>slot }
  end
  
  def slot_option(slot, args={}, &proc)
    args[:label] ||= args[:name]
    args[:editable]= true unless args.has_key?(:editable)
    slot.options_need_save = true if args[:editable]
    concat %{<tr>
      <td class="inline label"><label for="#{args[:name]}">#{args[:label]}</label></td>
      <td class="inline field">
    }, proc.binding
    yield
    concat %{
      </td>
      <td class="help">#{args[:help]}</td>
      </tr>
    }, proc.binding
  end

  def slot_link_to_action(slot, text, to_action, remote_opts={}, html_opts={})
    link_to_remote text, remote_opts.merge(
      :url=>slot.url_for("card/#{to_action}"),
      :update => slot.id
    ), html_opts
  end

  def slot_button_to_action(slot, text, to_action, remote_opts={}, html_opts={})
    button_to_remote text, remote_opts.merge(
      :url=>slot.url_for("card/#{to_action}"),
      :update => slot.id
    ), html_opts
  end
  
  
  def slot_link_to_menu_action(slot, to_action)
    slot.link_to_action to_action.capitalize, to_action, {},
      :class=> (slot.action==to_action ? 'current' : '')
  end
       
  def slot_render_partial(slot, partial, args={})
    # FIXME: this should look up the inheritance hierarchy, once we have one      
    args[:card] ||= slot.card
    args[:slot] =slot
    render :partial=> partial_for_action(partial, args[:card]), :locals => args
  end
  
  def slot_name_field(slot,form,options={})
    text = %{<span class="label"> card name:</span>\n}
    text << form.text_field( :name, options.merge(:size=>40, :class=>'field card-name-field'))
  end
  
  def slot_cardtype_field(slot,form,options={})
    card = options[:card] ? options[:card] : slot.card
    text = %{<span class="label"> card type:</span>\n} 
    text << select_tag('card[type]', cardtype_options_for_select(card.type), options.merge(:class=>'field')) 
  end
  
  def slot_update_cardtype_function(slot,options={})
    fn = ['File','Image'].include?(slot.card.type) ? 
            "Wagn.onSaveQueue['#{slot.id}'].clear(); " :
            "Wagn.runQueue(Wagn.onSaveQueue['#{slot.id}']); "
    fn << remote_function( options )   
  end
       
  def slot_js_content_element(slot)
    "$('#{slot.id(:form)}').elements['card[content]']"
  end
  
  def slot_content_field(slot,form,options={})   
    slot.form = form
    slot.render_partial 'editor', options
  end                          
         
  def slot_save_function(slot)
    "warn('runnint #{slot.id} queue'); if (Wagn.runQueue(Wagn.onSaveQueue['#{slot.id}'])) { this.form.onsubmit() }"
  end
  
  def slot_cancel_function(slot)
    "Wagn.runQueue(Wagn.onCancelQueue['#{slot.id}']);"
  end

  def slot_editor_hooks(slot,hooks)
    # it seems as though code executed inline on ajax requests works fine
    # to initialize the editor, but when loading a full page it fails-- so
    # we run it in an onLoad queue.  the rest of this code we always run
    # inline-- at least until that causes problems.
    code = ""
    if hooks[:setup]
      code << "Wagn.onLoadQueue.push(function(){\n" unless request.xhr?
      code << hooks[:setup]
      code << "});\n" unless request.xhr?
    end
    if hooks[:save]  
      code << "warn('adding to #{slot.id} save queue');"
      code << "if (typeof(Wagn.onSaveQueue['#{slot.id}'])=='undefined') {\n"
      code << "  Wagn.onSaveQueue['#{slot.id}']=$A([]);\n"
      code << "}\n"
      code << "Wagn.onSaveQueue['#{slot.id}'].push(function(){\n"
      code << "warn('running #{slot.id} save hook');"
      code << hooks[:save]
      code << "});\n"
    end
    if hooks[:cancel]
      code << "if (typeof(Wagn.onCancelQueue['#{slot.id}'])=='undefined') {\n"
      code << "  Wagn.onCancelQueue['#{slot.id}']=$A([]);\n"
      code << "}\n"
      code << "Wagn.onCancelQueue['#{slot.id}'].push(function(){\n"
      code << hooks[:cancel]
      code << "});\n"
    end
    javascript_tag code
  end
   
  def previous_page_function
    "document.location.href='#{url_for_page(previous_page)}'"
  end
  
  def truncatewords_with_closing_tags(input, words = 15, truncate_string = "...")
    if input.nil? then return end
    wordlist = input.to_s.split
    l = words.to_i - 1
    l = 0 if l < 0
    wordstring = wordlist.length > l ? wordlist[0..l].join(" ") : input
    h1 = {}
    h2 = {}
    wordstring.scan(/\<([^\>\s\/]+)[^\>\/]*?\>/).each { |t| h1[t[0]] ? h1[t[0]] += 1 : h1[t[0]] = 1 }
    wordstring.scan(/\<\/([^\>\s\/]+)[^\>]*?\>/).each { |t| h2[t[0]] ? h2[t[0]] += 1 : h2[t[0]] = 1 }
    h1.each {|k,v| wordstring += "</#{k}>" * (h1[k] - h2[k].to_i) if h2[k].to_i < v }
    wordstring += wordlist.length > l ? '<span style="color:grey"> ...</span' : ''
  end

  # You'd think we'd want to use this one but it sure doesn't seem to work as
  # well as the truncatewords...
  def truncate_with_closing_tags(input, chars, truncate_string = "...")
    if input.nil? then return end
      code = truncate(input, chars).to_s #.chop.chop.chop
      h1 = {}
      h2 = {}
      code.scan(/\<([^\>\s\/]+)[^\>\/]*?\>/).each { |t| h1[t[0]] ? h1[t[0]] += 1 : h1[t[0]] = 1 }
      code.scan(/\<\/([^\>\s\/]+)[^\>]*?\>/).each { |t| h2[t[0]] ? h2[t[0]] += 1 : h2[t[0]] = 1 }
      h1.each {|k,v| code += "</#{k}>" * (h1[k] - h2[k].to_i) if h2[k].to_i < v }
      code = code + truncate_string
      return code
  end  
   
  def conditional_cache(card, name, &block)
    card.cacheable? ? controller.cache_erb_fragment(block, name) : block.call
  end
  
  def rendered_content( card )   
    c, name = controller, "card/content/#{card.id}"
    if c.perform_caching and card.cacheable? and content = c.read_fragment(name)
      return content
    end
    content = render :partial=>partial_for_action("content", card), :locals=>{:card=>card}
    if card.cacheable? and c.perform_caching
      c.write_fragment(name, content)
    end
    content
  end

  def partial_for_action( name, card=nil )
    # FIXME: this should look up the inheritance hierarchy, once we have one
    cardtype = (card ? card.type : 'Basic').underscore
    file_exists?("/cardtypes/#{cardtype}/_#{name}") ? 
      "/cardtypes/#{cardtype}/#{name}" :
      "/cardtypes/basic/#{name}"
  end

  def formal_joint
    " <span class=\"wiki-joint\">#{JOINT}</span> "
  end
  
  def formal_title(card)
    card.name.split(JOINT).join(formal_joint)
  end
  
  def title_tag_names(card)
    card.name.split(JOINT)
  end
  
  # Urls -----------------------------------------------------------------------
  
  def url_for_page( title, opts={} )   
    # shaved order of magnitude off footer rendering
    # vs. url_for( :action=> .. )
    "/wiki/#{Cardname.escape(title)}"
    #url_for(opts.merge(
    #  :action=>'show', 
    #  :controller=>'card', 
    #  :id=>Cardname.escape(title), 
    #  :format => nil
    #))
  end  
  
  def url_for_card( options={} )
    url_for options_for_card( options )
  end
 
  # Links ----------------------------------------------------------------------
 
  def link_to_page( text, title=nil, options={} )
    title ||= text                              
    if (options.delete(:include_domain)) 
      link_to text, System.base_url.gsub(/\/$/,'') + url_for_page(title, :only_path=>true )
    else
      link_to text, url_for_page( title ), options
    end
  end  
    
  def link_to_connector_update( text, highlight_group, connector_method, value, *method_value_pairs )
    #warn "method_value_pairs: #{method_value_pairs.inspect}"
    extra_calls = method_value_pairs.size > 0 ? ".#{method_value_pairs[0]}('#{method_value_pairs[1]}')" : ''
    link_to_function( text, 
      "Wagn.highlight('#{highlight_group}', '#{value}'); " +
      "Wagn.lister().#{connector_method}('#{value}')#{extra_calls}.update()",
      :class => highlight_group,
      :id => "#{highlight_group}-#{value}"
    )
  end
  
  def link_to_options( element_id, args={} )
    args = {
      :show_text => "&raquo;&nbsp;show&nbsp;options", 
      :hide_text => "&laquo;&nbsp;hide&nbsp;options",
      :mode      => 'show'
    }.merge args
    
    off = 'display:none'
    show_style, hide_style = (args[:mode] != 'show' ?  [off, ''] : ['', off])     
    
    show_link = link_to_function( args[:show_text], 
        %{ Element.show("#{element_id}-hide");
           Element.hide("#{element_id}-show");
           Effect.BlindDown("#{element_id}", {duration:0.4})
         },
         :id=>"#{element_id}-show",
         :style => show_style
     )
     hide_link = link_to_function( args[:hide_text],
        %{ Element.hide("#{element_id}-hide"); 
           Element.show("#{element_id}-show"); 
           Effect.BlindUp("#{element_id}", {duration:0.4})
        },
        :id=>"#{element_id}-hide", 
        :style=>hide_style
      )
      show_link + hide_link 
  end
  
  def name_in_context(card, context_card)
    context_card == card ? card.name : card.name.gsub(context_card.name, '')
  end
  
  def fancy_title(card) fancy_title_from_tag_names(card.name.split( JOINT ))  end
  
  def query_title(query, card_name)
    title = {
      :plus_cards => "Junctions: we join %s to other cards",
      :plussed_cards => "Joinees: we're joined to %s",
      :backlinks => 'Links In: we link to %s',
      :linksout => "Links Out: %s links to us",
      :cardtype_cards => card_name.pluralize + ': our cardtype is %s',
      :pieces => 'Pieces: we join to form %s',
      :revised_by => 'Edits: %s edited these cards'
    }
    title[query.to_sym] % ('"' + card_name + '"')
  end
  
  def query_options(card)
    options_for_select card.queries.map{ |q| [query_title(q,card.name), q ] }
  end
  
  def fancy_title_from_tag_names(tag_names)
    tag_names.inject([nil,nil]) do |title_array, tag_name|
      title, title_link = title_array
      tag_link = link_to tag_name, url_for_page( tag_name ), :class=>"link-#{css_name(tag_name)}"
      if title 
        title = [title, tag_name].join(%{<span class="joint">#{JOINT}</span>})
        joint_link = link_to formal_joint, url_for_page(title), 
          :onmouseover=>"Wagn.title_mouseover('title-#{css_name(title)} card')",
          :onmouseout=>"Wagn.title_mouseout('title-#{css_name(title)} card-highlight')"
        title_link = "<span class='title-#{css_name(title)} card' >\n%s %s %s\n</span>" % [title_link, joint_link, tag_link]
        [title, title_link]
      else
        [tag_name, %{<span class="title-#{css_name(tag_name)} card">#{tag_link}</span>\n}]
      end
    end[1]
  end

  def less_fancy_title(card)
    name = card.name
    return name if name.simple?
    card_title_span(name.parent_name) + %{<span class="joint">#{JOINT}</span>} + card_title_span(name.tag_name)
  end
  
  def card_title_span( title )
    %{<span class="title-#{css_name(title)} card">#{title}</span>}
  end
  
  def connector_function( name, *args )
    "Wagn.lister().#{name.to_s}(#{args.join(',')});"
  end             
  
  def pieces_icon( card, prefix='' )
    image_tag "/images/#{prefix}pieces_icon.png", :title=>"cards that comprise \"#{card.name}\""
  end
  def connect_icon( card, prefix='' )
    image_tag "/images/#{prefix}connect_icon.png", :title=>"plus cards that include \"#{card.name}\""
  end
  def connected_icon( card, prefix='' )
    image_tag "/images/#{prefix}connected_icon.png", :title=>"cards connected to \"#{card.name}\""
  end
  
  def page_icon (card)
    link_to_page image_tag('page.png', :title=>"Card Page for: #{card.name}"), card.name
  end
  # Other snippets -------------------------------------------------------------

  def site_name
    System.site_name
  end
    
  def css_name( name )
    name.gsub(/#{'\\'+JOINT}/,'-').gsub(/[^\w-]+/,'_')
  end
  
  def related
    render :partial=> 'card/related'
  end
  
  def sidebar
    render :partial=>partial_for_action('sidebar', @card)
  end

  def format_date(date, include_time = true)
    # Must use DateTime because Time doesn't support %e on at least some platforms
    if include_time
      DateTime.new(date.year, date.mon, date.day, date.hour, date.min, date.sec).strftime("%B %e, %Y %H:%M:%S")
    else
      DateTime.new(date.year, date.mon, date.day).strftime("%B %e, %Y")
    end
  end

  def flexlink( linktype, name, options )
    case linktype
      when 'connect'
        link_to_function( name,
           "var form = window.document.forms['connect'];\n" +
           "form.elements['name'].value='#{name}';\n" +
           "form.onsubmit();",
           options)
      when 'page'
        link_to_page name, name, options
      else
        raise "no linktype specified"
    end
  end
  
  def createable_cardtypes
    session[:createable_cardtypes]
  end
    

  ## ----- for Linkers ------------------  
  def cardtype_options
    createable_cardtypes.map do |cardtype|
      next if cardtype[:codename] == 'User' #or cardtype[:codename] == 'InvitationRequest'
      [cardtype[:codename], cardtype[:name]]
    end.compact
  end

  def cardtype_options_for_select(selected=Card.default_cardtype_key)
    #warn "SELECTED = #{selected}"
    options_from_collection_for_select(cardtype_options, :first, :last, selected)
  end

  def paging( cards )
    links = ""
    page = (params[:page] || 1).to_i 
    pagesize = (params[:pagesize] || System.pagesize).to_i
        
    if page > 1
      links << link_to_function( image_tag('prev-page.png'), "Wagn.lister().page(#{page-1}).update()")
    else
      links << image_tag('no-prev-page.png')
    end     
    offset = pagesize * (page-1)                
    links << " #{cards.length > 0 ? offset+1 : 0}-#{offset+cards.length} "     

    if cards.length == pagesize
      links << link_to_function( image_tag('next-page.png'), "Wagn.lister().page(#{page+1}).update()")   
    else
      links << image_tag('no-next-page.png')
    end
    %{<span id="paging-links" class="paging-links">#{links}</span>}
  end

  def button_to_remote(name,options={},html_options={})
    button_to_function(name, remote_function(options), html_options)
  end          
  
  
  def stylesheet_inline(name)
    out = %{<style type="text/css" media="screen">\n}
    out << File.read("#{RAILS_ROOT}/public/stylesheets/#{name}.css")
    out << "</style>\n"
  end
  
end



