class Wagn::Renderer
  define_view(:naked, :type=>'search') do
    error=nil
    results = begin
      card.item_cards( paging_params )
    rescue Exception=>e
      error = e; nil
    end

    case
    when results.nil?
      %{No results? #{error.class.to_s}: #{error&&error.message}<br/>#{card.content}}
    when card.spec[:return] =='count'
      results.to_s
    else
      render('card_list', :results=>results)
    end
  end
  
  define_view(:editor, :type=>'search') do
    form.text_area :content, :rows=>10
  end

  define_view(:closed_content, :type=>'search') do
    return "..." if depth > 2
    results= begin
      card.item_cards( paging_params )
    rescue Exception=>e
      error = e; nil
    end

    if results.nil?
      %{"#{error.class.to_s}: #{error.message}"<br/>#{card.content}}
    elsif card.spec[:return] =='count'
      results.to_s
    elsif results.length==0
      '<span class="faint">(0)</span>'
    else
      %{<span class="faint">(#{ card.count })</span>
      <div class="search-result-list">
        #{results.map do |c|
          %{<div class="search-result-item">#{'name' == item_view || params[:item] ? c.name : link_to_page( c.name ) }</div>}
        end*"\n"}
      </div>}
    end
  end


  define_view(:card_list, :type=>'search') do |args|
    cards = args[:results]
    @item_view ||= (card.spec[:view]) || :closed

    instruction, title = nil,nil
    if card.name=='*search'
      instruction = %{Cards matching keyword: <strong class="keyword">#{paging_params[:_keyword]}</strong>} #ENGLISH
      title = 'Search Results' #ENGLISH
    end

    paging = render(:paging, :results=>cards)

    # now the result string ...
    if title
      %{<h1 class="page-header">#{ title }</h1>}
    else '' end +
    if instruction; %{
<div class="instruction">
    <p>#{ instruction }</p>
  </div>}
    else '' end +
    if cards.empty?
      %{<div class="search-no-results"></div>}
    else %{#{paging}
  <div class="search-result-list"> #{
      cards.map do |c|
        %{<div class="search-result-item item-#{ @item_view }">#{
        process_inclusion(c, :view=>@item_view) }</div>}
      end.join }
  </div>#{ paging }}
    end
  end




  define_view(:card_list, :name=>'*recent') do |args|
    cards = args[:results]
    @item_view ||= (card.spec[:view]) || :change

    cards_by_day = Hash.new { |h, day| h[day] = [] }
    cards.each do |card|
      begin
        stamp = card.updated_at
        day = Date.new(stamp.year, stamp.month, stamp.day)
      rescue Exception=>e
        day = Date.today
        card.content = "(error getting date)"
      end
      cards_by_day[day] << card
    end

    paging = render(:paging, :results=>cards)
%{<h1 class="page-header">Recent Changes</h1>
<div class="card-slot recent-changes">
  <div class="open-content">
    #{ paging }
  } +
    cards_by_day.keys.sort.reverse.map do |day| 
      
%{  <h2>#{format_date(day, include_time = false) }</h2>
    <div class="search-result-list">} +
         cards_by_day[day].map do |card| %{
      <div class="search-result-item item-#{ @item_view }">
           #{process_inclusion(card, :view=>@item_view) }
      </div>}
         end.join(' ') + %{
    </div>
    } end.join("\n") + %{    
      #{ paging }
  </div>
</div>
}
  end



  define_view(:paging, :type=>'search') do |args|
    results = args[:results]
    s = card.spec(paging_params)
    offset, limit = s[:offset].to_i, s[:limit].to_i
    first,last = offset+1,offset+results.length 
    total = card.count(paging_params)
 
    args = params.clone
    args[:limit] = limit

    args[:requested_view] = requested_view 
    args[:item] = item_view || args[:item]
    args[:_keyword] = s[:_keyword] if s[:_keyword]

    %{
<!-- paging -->#{
      if total > limit
        %{
<span class="paging">#{
        if first > 1
          link_to_remote image_tag('prev-page.png'), :update=>id,
            :url=>url_for('card/view', args.merge(:offset=>[offset-limit,0].max)) 
        end}
  <span class="paging-range">#{ first } to #{ last } of #{ total }</span>#{
        if last < total
          link_to_remote image_tag('next-page.png'), :update=>id,
             :url=>url_for('card/view', args.merge(:offset=>last))
        end}
  </span>}
      end}
<!-- /paging -->}
  end


  def paging_params
    if ajax_call? && @depth > 0
      {:default_limit=>20}  #important that paging calls not pass variables to included searches
    else
      @paging_params ||= begin
        s = {}
        if p = root.params
          [:offset,:limit,:_keyword].each{|key| s[key] = p.delete(key)}
        end
        s[:offset] = s[:offset] ? s[:offset].to_i : 0
        if s[:limit]
          s[:limit] = s[:limit].to_i
        else
          s.delete(:limit)
          s[:default_limit] = (main_card? ? 50 : 20) #can be overridden by card value
        end
        s
      end
    end
  end



#  define_view(:tag_cloud, :type=>'search') do
#    cards ||= []
#    link_to ||= 'page'  # other options is 'connect'
#    tag_cloud = {}
#    category_list = %w[1 2 3 4 5]
#    droplets = []
#    return if cards.empty?
#
#    # this does scaling by rank(X), where X is what we ordered by in wql.
#    # if we wanted proportionate to X, we'd need to get X returned as part of
#    # the cards, which has implications for wql; namely we'd need to be able to
#    # return additional fields.
#    cards.reverse.each_with_index do |tag, index|
#      tag_cloud[tag] = index
#    end
#
#    max, min = 0, 0
#    tag_cloud.each_value do |count|
#      max = count if count > max
#      min = count if count < min
#    end
#
#    divisor = ((max - min) / category_list.size) + 1
#
#    droplets = cards.sort_by {|c| c.name.downcase } .map do |card|
#      category = category_list[(tag_cloud[card] - min) / divisor]
#      options = { :class=>"cloud-#{category}" }
#      WagnHelper::Droplet.new(card.name, options)
#    end
#    %{
#<div class="cloud">#{
#      for droplet in droplets 
#        flexlink link_to, droplet.name,  droplet.link_options
#      end * "\n" }
#</div>}
#  end
end
