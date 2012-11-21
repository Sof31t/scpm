require 'spreadsheet'
class SpidersController < ApplicationController
  layout :resolve_layout, :except => :generate_kpi_charts_data
  
  def resolve_layout
     case action_name
     when "kpi_charts_by_pm_types","kpi_charts_by_axes", "kpi_cumul_charts_by_axes", "kpi_cumul_charts_by_pm_types", "project_spider_import", "do_spider_upload"
       "tools_spider"
     else
       "spider"
     end
   end
   
  # ------------------------------------------------------------------------------------
  # BASE : ACTION/VIEW
  # ------------------------------------------------------------------------------------
  
  # Spider page for a project
  def project_spider
    # Search project from parameter
    id = params[:project_id]
    @project = Project.find(id)
    
    # search milestonename from parameter
    milestoneId = params[:milestone_id]
    @milestone = Milestone.find(milestoneId)
    
    # create new spider parameter
    create_spider_param = params[:create_spider]    
    
    # call generate_current_table
    generate_current_table(@project,@milestone,create_spider_param)
    # Search all spider from history (link)
    create_spider_history(@project,@milestone)
  end
  
  # History of one spider
  def project_spider_history
    # Search project for paramater
    id = params[:spider_id]
    @spider = Spider.find(id)
    # generate_table_history
    generate_table_history(@spider)
  end
  
  # Export excel from project
  def project_spider_export
    begin
      @project = Project.find(params[:project_id])
      @pm_type_hash = Hash.new
      @xml = Builder::XmlMarkup.new(:indent => 1) #Builder::XmlMarkup.new(:target => $stdout, :indent => 1)
    
      # Cache for milestones and spider
      cache_milestone = Array.new
      cache_spider = Hash.new
    
      @project.milestones.each { |mi|
        cache_milestone<<mi
        cache_spider[mi.id] = Spider.last(
        :joins => 'JOIN spider_consolidations ON spiders.id = spider_consolidations.spider_id',
        :conditions => ['milestone_id = ? ',mi.id])
      }
    
      PmType.find(:all).each { |pm|  
        # Params
        @pm_type_hash[pm.id] = Hash.new
        @pm_type_hash[pm.id]["title"] = pm.title
        @pm_type_hash[pm.id]["axe_hash"] = Hash.new
      
        #pm.pm_type_axes.each { |axe|
        PmTypeAxe.find(:all,:include => :lifecycle_questions , :conditions => ["pm_type_id = ? and lifecycle_questions.lifecycle_id = ?", pm.id, @project.lifecycle_id]).each{ |axe|
          # Params
          @pm_type_hash[pm.id]["axe_hash"][axe.id] = Hash.new
          @pm_type_hash[pm.id]["axe_hash"][axe.id]["title"] = axe.title
          @pm_type_hash[pm.id]["axe_hash"][axe.id]["milestone_hash"] = Hash.new

          # Get milestones
          cache_milestone.each { |mi|
            # Params
            @pm_type_hash[pm.id]["axe_hash"][axe.id]["milestone_hash"][mi.id] = Hash.new
            @pm_type_hash[pm.id]["axe_hash"][axe.id]["milestone_hash"][mi.id]["title"] = mi.name
            @pm_type_hash[pm.id]["axe_hash"][axe.id]["milestone_hash"][mi.id]["question_hash"] = Hash.new
          
            last_spider = cache_spider[mi.id]
            # Get spiders conso for this project, this milestone, this axe, and last spider
            @pm_type_hash[pm.id]["axe_hash"][axe.id]["milestone_hash"][mi.id]["spider_conso"] = 0
            if((last_spider) and (last_spider.spider_consolidations.count > 0))
              last_spider.spider_consolidations.each { |conso|
                if (conso.pm_type_axe_id == axe.id)
                  @pm_type_hash[pm.id]["axe_hash"][axe.id]["milestone_hash"][mi.id]["spider_conso"] = conso
                end
              }
            end
            LifecycleQuestion.all(:conditions => ["lifecycle_id = ? and pm_type_axe_id = ?",@project.lifecycle_id,axe.id] ).each{ |quest|
              # Params
              @pm_type_hash[pm.id]["axe_hash"][axe.id]["milestone_hash"][mi.id]["question_hash"][quest.id] = Hash.new
              @pm_type_hash[pm.id]["axe_hash"][axe.id]["milestone_hash"][mi.id]["question_hash"][quest.id]["text"] = quest.text
                  
              # Get spiders values for this project, this milestone, this axe, and last spider
              @pm_type_hash[pm.id]["axe_hash"][axe.id]["milestone_hash"][mi.id]["question_hash"][quest.id]["spider_value"] = 0
              
              if(last_spider)
                last_spider.spider_values.each { |sv| 
                  if (sv.lifecycle_question_id == quest.id)
                    @pm_type_hash[pm.id]["axe_hash"][axe.id]["milestone_hash"][mi.id]["question_hash"][quest.id]["spider_value"] = sv
                  end
                }
              end
           }
          }
        }
      }
   
      headers['Content-Type']         = "application/vnd.ms-excel"
      headers['Content-Disposition']  = 'attachment; filename="spiders_export_'+@project.workstream+'_'+@project.id.to_s+'.xls"'
      headers['Cache-Control']        = ''
    rescue Exception => e
      render(:text=>"<b>#{e}</b><br/>#{e.backtrace.join("<br/>")}")
    end
    render(:layout=>false)
  end
  
  def project_spider_import
  end
  
  #http://0.0.0.0:3000/spiders/kpi_charts_by_pm_types?lifecycle_id=1&workstream=0&milestone_name_id=0
  def kpi_charts_by_pm_types 
    @chart_type_param = "classic"
    @kpi_type_param = "pm_type" 
    kpi_prepare_parameters
    render :kpi_charts
  end
  
  def kpi_charts_by_axes  
    @chart_type_param = "classic"
    @kpi_type_param = "pm_type_axe"
    kpi_prepare_parameters
    render :kpi_charts
  end
  
  def kpi_cumul_charts_by_pm_types  
    @chart_type_param = "cumul"
    @kpi_type_param = "pm_type" 
    kpi_prepare_parameters
    render :kpi_charts
  end
  
  def kpi_cumul_charts_by_axes   
    @chart_type_param = "cumul"
    @kpi_type_param = "pm_type_axe"
    kpi_prepare_parameters
    render :kpi_charts
  end

  # ------------------------------------------------------------------------------------
  # CREATE HTML ELEMENTS
  # ------------------------------------------------------------------------------------
  
  # Generate data for the current spider
  def generate_current_table(currentProject,currentMilestone,newSpiderParam)
    @currentProjectId = currentProject.id
    @currentMilestoneId = currentMilestone.id
    @pmType = Hash.new
    @questions = Hash.new
    @questions_values = Hash.new
    @spider = nil
    
    # Search the last spider with are not consolidated
    last_spider = Spider.last(:conditions => ["milestone_id= ?", currentMilestone.id])
    
    # If not spider currently edited
    if ((!last_spider) || (last_spider.spider_consolidations.count != 0))
      # If create mode
      if (newSpiderParam == "1")
        last_spider = create_spider_object(currentProject,currentMilestone)
      end
    end
    
    if ((last_spider) && (last_spider.spider_consolidations.count == 0))
      @spider = last_spider
    
      # Search questions for this project
      # For Each PM Type
      PmType.find(:all).each{ |p|
        @pmType[p.id] = p.title
        # All Axes
        pmTypeAxe_ids = PmTypeAxe.all(:conditions => ["pm_type_id = ?", p.id]).map{ |pa| pa.id }
        # All questions
        @questions[p.id] = SpiderValue.find(:all,
        :include => :lifecycle_question,
        :conditions => ['spider_id = ? and lifecycle_questions.pm_type_axe_id IN (?)', @spider.id,pmTypeAxe_ids],
        :order => "lifecycle_questions.pm_type_axe_id ASC")
      }

    end
  end

  # Generate data for the history spider selected
  def generate_table_history(spiderParam)
    @pmType = Hash.new
    @consoByPmType = Hash.new
    @axesValues = Hash.new
    
    # For Each PM Type
    PmType.find(:all).each{ |p|
      @pmType[p.id] = p.title
      
      @consoByPmType[p.id] = SpiderConsolidation.find(:all,
      :include => :pm_type_axe,
      :conditions => ['spider_id = ? and pm_type_axes.pm_type_id = ?', spiderParam.id,p.id],
      :order => "pm_type_axes.id ASC")
      
      @consoByPmType[p.id].each { |c|        
          @axesValues[c.pm_type_axe_id] = SpiderValue.find(:all,
              :include => :lifecycle_question,
              :conditions => ['spider_id = ? and lifecycle_questions.pm_type_axe_id = ?', spiderParam.id,c.pm_type_axe_id],
              :order => "lifecycle_questions.pm_type_axe_id ASC")
      }      
    }  
  end

  # Get links of consolidations for one spider
  def create_spider_history(projectSpider,milestoneSpider)
    @history = Array.new
    Spider.find(:all,
    :select => "DISTINCT(spiders.id),spiders.created_at",
    :joins => 'JOIN spider_consolidations ON spiders.id = spider_consolidations.spider_id',
    :conditions => ["milestone_id= ?", milestoneSpider.id]).each { |s|
      @history.push(s)
    }
  end

  # ------------------------------------------------------------------------------------
  # FORMS MANAGEMENT
  # ------------------------------------------------------------------------------------
  
  # Save spider
  def update_spider
      spider = Spider.find(params[:spider_id])
      spiderValues = params[:spiderquest]
      spiderValues.each { |h|
        currentQuestion = SpiderValue.find(h[0])
        currentQuestion.note = h[1].to_s
        currentQuestion.save
      }
      if(params[:consolidate_spider] == "1")
        project_spider_consolidate(spider)
     end
     redirect_to :action=>:project_spider, :project_id=>params[:project_id], :milestone_id=>params[:milestone_id]
  end
  
  # Consolidate the spider
  def project_spider_consolidate(spiderParam)
    currentAxes = ""
    currentAxesId = 0;
    valuesTotal = 0
    valuesCount = 0
    referencesTotal = 0
    referencesCount = 0
    niCount = 0
    i = 0;
    
    SpiderValue.find(:all, 
    :joins => 'LEFT OUTER JOIN lifecycle_questions ON spider_values.lifecycle_question_id = lifecycle_questions.id',
    :conditions => ['spider_id = ?', spiderParam.id],
    :order => "lifecycle_questions.pm_type_axe_id ASC").each { |v|          
      # If new axes
      if(currentAxes != v.lifecycle_question.pm_type_axe.title)  
          if(i!=0)
            # Save data in consolidate table
            create_spider_conso(spiderParam,currentAxesId,valuesTotal,valuesCount,referencesTotal,referencesCount,niCount)             
          end
          currentAxes = v.lifecycle_question.pm_type_axe.title
          currentAxesId = v.lifecycle_question.pm_type_axe.id
          valuesTotal = 0
          valuesCount = 0
          referencesTotal = 0
          referencesCount = 0
          niCount = 0
      end
      
      if(v.note == "NI")
        niCount = niCount.to_i + 1
        valuesTotal = valuesTotal.to_f + 0
        valuesCount = valuesCount.to_i + 1
      else
        valuesTotal = valuesTotal.to_f + v.note.to_f
        valuesCount = valuesCount.to_i + 1
      end
      referencesTotal = referencesTotal.to_f + v.reference.to_f
      referencesCount = referencesCount.to_i + 1
      i = i + 1
    }
    # Save data of last element
    create_spider_conso(spiderParam,currentAxesId,valuesTotal,valuesCount,referencesTotal,referencesCount,niCount)
  end
  
  # Import file
  def do_spider_upload
    
    # INDEX OF COLUMNS IN EXCEL ------------------------
    @practiceStartColumn = 9
    @practiceEndColumn = 0
    @deliverableStartColumn = 0
    @deliverableEndColumn = 0
    
    # LOAD FILE --------------------------------- 
    consoSheet = load_spider_excel_file(params[:upload])
    
    # ANALYSE HEADER OF FILE ---------------------------------
    axesHash = analyze_spider_excel_file_header(consoSheet)
    
    # ANALYSE CONSOS OF FILE ---------------------------------
    projectsArray = analyze_spider_excel_file_conso(consoSheet, axesHash)
    
    # IMPORT DATA IN BDD ---------------------------------
    @projectsNotFound = Array.new
    @milestonesNotFound = Array.new
    @axesNotFound = Array.new
    @projectsAdded = Array.new
    
    # For each projects
    projectsArray.each { |project| 
         	
    	# Search project in BAM
    	bam_project = Project.last(:conditions=>["name = ?", project["title"]])
    	if(bam_project != nil)
    	  
    	  # Search milestone
    	  milestoneList = Array.new
    	  if (project["milestone"].count('-') > 0)
    	    milestoneList = project["milestone"].split('-')
    	  else
    	    milestoneList << project["milestone"]
    	  end 
    	  
    	  # For each milestones of project in BAM
    	  milestoneList.each { |project_milestone|
    	    
    	    bam_milestone = Milestone.last(:conditions =>["name = ? and project_id = ?", project_milestone, bam_project.id])
    	    
    	    if(bam_milestone != nil)
    	          	          	      
      	    # Create Spider for this project
    	      new_spider = create_spider_object(bam_project,bam_milestone)
    	      new_spider.created_at = project["date"]
    	      new_spider.save
  	        @projectsAdded << "Project : "+ bam_project.name + " - Milestone : " + project_milestone
    	      # For each conso
    	      project["conso"].each do |conso|
  	        
    	        axe_title = conso[0]
    	        if (axe_title[-1,1] == " ")
    	          axe_title = axe_title[0..-2]
    	        end
    	        if(axe_title[0,1] == " ")
    	          axe_title = axe_title[1..-1]
    	        end
  	          pm_type = axesHash[conso[1]["column_ids"].last.to_i]["type"]
  	        
    	        if(conso[1]["column_ids"][2].to_i <= @deliverableEndColumn)
        	      # Search type
        	      bam_pm_type = PmType.first(:conditions => ["title LIKE ?", "%"+pm_type+"%"])
      	        # Search Axes
      	        bam_axe = PmTypeAxe.first(:conditions => ["pm_type_id = ? and title LIKE ?", bam_pm_type.id, "%"+axe_title+"%"])
      	        # Axes if not found
      	        if (bam_axe != nil)
      	          # Add spider conso
      	          create_spider_history_conso(new_spider,bam_axe.id, project["date"], conso[1]["values"][0],conso[1]["values"][1],conso[1]["values"][2])
      	        else
      	          @axesNotFound << "Project : "+ bam_project.name + " - Milestone : " + project_milestone + " - Axe : " + axe_title + " not found."
      	        end
      	      end
    	      end
      	  
    	    else
    	      @milestonesNotFound << "Project : "+ bam_project.name + " - Milestone : " + project_milestone + " not found."
    	    end 
    	  }
    	else
    	  @projectsNotFound << "Project " + project["title"] + " not found"
    	end
    }
  end
  
  # ------------------------------------------------------------------------------------
  # OBJECTS MANAGEMENT
  # ------------------------------------------------------------------------------------
  
  # Create spider object with questions
  def create_spider_object(projectSpider,milestoneSpider)
    new_spider = Spider.new()
    new_spider.project_id = projectSpider.id
    new_spider.milestone_id = milestoneSpider.id
    new_spider.save
    
    # Generate Spider_responses
    LifecycleQuestion.all(:conditions => ["lifecycle_id = ?", projectSpider.lifecycle_id]).each { |q|
      # Get reference for this question and milestone
      m = MilestoneName.find_by_title(milestoneSpider.name)
      new_question_reference = QuestionReference.first(:conditions => ["question_id = ? and milestone_id = ?", q.id, m.id])
      
      # Creation question value
      new_spider_value = SpiderValue.new
      new_spider_value.lifecycle_question_id = q.id
      new_spider_value.spider_id = new_spider.id
      if(new_question_reference)
        new_spider_value.reference = new_question_reference.note
      else
        new_spider_value.reference = "NI"
      end
      
      new_spider_value.save
    }
    return new_spider
  end
  
  # Create spider consolidation
  def create_spider_conso(spiderParam, axesIdParam, valuesTotalParam,valuesCountParam,referencesTotalParam,referencesCountParam,niCountParam)
    new_spider_conso = SpiderConsolidation.new
    if(valuesCountParam != 0)
      new_spider_conso.average = valuesTotalParam.to_f / valuesCountParam.to_f
    else
      new_spider_conso.average = 0
    end
    if(referencesCountParam != 0)
      new_spider_conso.average_ref = referencesTotalParam.to_f / referencesCountParam.to_f
    else
      new_spider_conso.average_ref = 0
    end
    new_spider_conso.ni_number = niCountParam
    new_spider_conso.spider_id = spiderParam.id
    new_spider_conso.pm_type_axe_id = axesIdParam
    new_spider_conso.save
  end
  
  # Used when data import
  def create_spider_history_conso(spiderParam, axesIdParam, date, valuesTotalParam,referencesTotalParam,niCountParam)
    new_spider_conso = SpiderConsolidation.new
    
    if(valuesTotalParam)
      new_spider_conso.average = valuesTotalParam.to_f
    else
      new_spider_conso.average = 0
    end
    
    if(referencesTotalParam)
      new_spider_conso.average_ref = referencesTotalParam.to_f
    else
      new_spider_conso.average_ref = 0
    end
    
    if(niCountParam)
      new_spider_conso.ni_number = niCountParam
    else
      new_spider_conso.ni_number = 0
    end
    
    new_spider_conso.spider_id = spiderParam.id
    new_spider_conso.pm_type_axe_id = axesIdParam
    new_spider_conso.created_at = date
    new_spider_conso.save
  end
  
  # ------------------------------------------------------------------------------------
  # KPI FUNCTIONS
  # ------------------------------------------------------------------------------------
  def kpi_prepare_parameters
    @lifecycles = Lifecycle.all.map {|u| [u.name,u.id]}    
    @milestones = MilestoneName.all.map {|u| [u.title,u.id]} 
    @milestones.insert(0,["None",0])
    @workstreams = Workstream.all.map {|u| [u.name,u.name]}
    @workstreams.insert(0,["None",0])
    
    @lifecycle_id = params[:lifecycle_id]
    @workstream = params[:workstream]
    @milestone_name_id = params[:milestone_name_id]
    
    # CHART TYPE --------------------------------- 
    @kpi_type = ""
    if (@kpi_type_param != nil)
      @kpi_type = @kpi_type_param
    else
      @kpi_type = params[:kpi_type]
    end
    charts_element = Array.new
    if (@kpi_type == "pm_type")
      charts_element = PmType.all
    else
      charts_element = PmTypeAxe.all
    end
    
    @chart_type = ""
    if(@chart_type_param != nil)
      @chart_type = @chart_type_param
    else
      @chart_type = params[:chart_type]
    end
    
  end
  
  # Get all spiders which need to be used in KPI
  def get_spiders_consolidated(lifecycle,workstream,milestone)
    spiders_consolidated = Array.new
    
    spider_conso_query = "SELECT s.id,s.milestone_id FROM spiders s, spider_consolidations sc, milestones m, projects p, milestone_names as mn "
    spider_conso_query += " WHERE sc.spider_id = s.id"
    spider_conso_query += " AND s.milestone_id = m.id"
    spider_conso_query += " AND m.project_id = p.id"
    spider_conso_query += " AND m.name = mn.title"
    if ((workstream != nil) && (workstream != "0"))
      spider_conso_query += " AND p.workstream = '" + workstream + "'"
    end
    if ((milestone != nil) && (milestone != "0"))
      spider_conso_query += " AND mn.id = " + milestone
    end
    spider_conso_query += " AND s.created_at = (SELECT MAX(sbis.created_at) FROM spiders sbis WHERE id = s.id)"
    spider_conso_query += " GROUP BY s.milestone_id"
    
    ActiveRecord::Base.connection.execute(spider_conso_query).each do |spider|
      spiders_consolidated << spider[0].to_s
    end
    
    if spiders_consolidated.count == 0
      spiders_consolidated << 0
    end
    return spiders_consolidated
  end
  
  def generate_kpi_charts_data
    @lifecycle_id = params[:lifecycle_id]
    lifecycle_title = Lifecycle.find(@lifecycle_id).name
    @workstream = params[:workstream]
    @milestone_name_id = params[:milestone_name_id]
    milestone_title = ""
    if ((@milestone_name_id != nil) and (@milestone_name_id != "0"))
      milestone_title = MilestoneName.find(@milestone_name_id)
    end
    
    # CHART TYPE --------------------------------- 
    @kpi_type = ""
    if (@kpi_type_param != nil)
      @kpi_type = @kpi_type_param
    else
      @kpi_type = params[:kpi_type]
    end
    charts_element = Array.new
    if (@kpi_type == "pm_type")
      charts_element = PmType.all
    else
      charts_element = PmTypeAxe.all
    end

    @chart_type = ""
    if(@chart_type_param != nil)
      @chart_type = @chart_type_param
    else
      @chart_type = params[:chart_type]
    end

    spiders_consolidated = get_spiders_consolidated(@lifecycle_id,@workstream, @milestone_name_id)
    
    # MONTHS CALCUL --------------------------------- 
    timeline_size = 19 # in months
    
    # @months_array = Array.new
    now_dateTime = DateTime.now.to_time
    last_month = now_dateTime - 1.month
    
    temp_date_end = now_dateTime
    sql_query_end = temp_date_end.strftime("%Y-%m-01 00:00")   
    last_month_ref =  last_month.month   
    last_year_ref = last_month.year 
    
    temp_date_begin = last_month - timeline_size.month
    sql_query_begin = temp_date_begin.strftime("%Y-%m-01 00:00:00")
    first_month_ref =  temp_date_begin.strftime("%m")   
    first_year_ref = temp_date_begin.strftime("%Y")

    # REQUEST --------------------------------- 

    # MULTIPLE GROUP BY : Seem broken (https://rails.lighthouseapp.com/projects/8994/tickets/497-activerecord-calculate-broken-for-multiple-fields-in-group-option)
    # So I use a SQL Query (yes, it's ugly in a RoR project)
    
    @charts_data = Hash.new
    @titles_data = Hash.new
    charts_element.each do |chart_element|
      query = "SELECT avg(sc.average),MONTH(sc.created_at),YEAR(sc.created_at) 
      FROM spider_consolidations sc,  pm_type_axes pta
      WHERE sc.pm_type_axe_id = pta.id
      AND sc.spider_id IN (" + spiders_consolidated.join(",") + ")"
      query += " AND sc.created_at >= '" + sql_query_begin.to_s + "'"
      query += " AND sc.created_at <= '" + sql_query_end.to_s + "'"
      
      if (@kpi_type == "pm_type")
        query += " AND pta.pm_type_id = " + chart_element.id.to_s
      else
        query += " AND pta.id = " + chart_element.id.to_s
      end
      
      query += " GROUP BY MONTH(created_at),YEAR(created_at) 
      ORDER BY YEAR(created_at),MONTH(created_at)";
      
      # Analyse return data
      @charts_data[chart_element.id.to_s] = Array.new
      charts_data_by_date = Hash.new
      
      # Save query data in hash[month-year]
      ActiveRecord::Base.connection.execute(query).each do |query_data|
        charts_data_by_date[query_data[1]+"-"+query_data[2]] = query_data
      end
      
      # Check if we have all months/years
      month_index = 0
      (Date.new(first_year_ref.to_i, first_month_ref.to_i)..Date.new(last_year_ref.to_i, last_month_ref.to_i)).select {|d| 
        if (month_index.to_i != d.month.to_i)
          if(charts_data_by_date[d.month.to_s+"-"+d.year.to_s] != nil)
            @charts_data[chart_element.id.to_s] << charts_data_by_date[d.month.to_s+"-"+d.year.to_s]
          else
            unassigned_month = Array.new<<0<<d.month.to_i<<d.year.to_i
            @charts_data[chart_element.id.to_s] << unassigned_month
          end
          month_index = d.month
        end
      }
      
      # Set title
      title = lifecycle_title
      if ((@workstream != nil) and (@workstream != "0"))
        title += " - " + @workstream
      end
      if ((milestone_title != nil) and (milestone_title != ""))
        title += " - " + milestone_title.title
      end
      
      @titles_data[chart_element.id.to_s] = title + " - " + chart_element.title  
    end

    if(@kpi_type_param == nil)
      render :layout => false     
    end
  end
  
  def generate_kpi_cumul_charts_data
    @lifecycle_id = params[:lifecycle_id]
    lifecycle_title = Lifecycle.find(@lifecycle_id).name
    @workstream = params[:workstream]
    @milestone_name_id = params[:milestone_name_id]
    milestone_title = ""
    if ((@milestone_name_id != nil) and (@milestone_name_id != "0"))
      milestone_title = MilestoneName.find(@milestone_name_id)
    end
    
    # CHART TYPE --------------------------------- 
    @kpi_type = ""
    if (@kpi_type_param != nil)
      @kpi_type = @kpi_type_param
    else
      @kpi_type = params[:kpi_type]
    end
    charts_element = Array.new
    if (@kpi_type == "pm_type")
      charts_element = PmType.all
    else
      charts_element = PmTypeAxe.all
    end

    @chart_type = ""
    if(@chart_type_param != nil)
      @chart_type = @chart_type_param
    else
      @chart_type = params[:chart_type]
    end

    spiders_consolidated = get_spiders_consolidated(@lifecycle_id,@workstream, @milestone_name_id)
    
    # MONTHS CALCUL --------------------------------- 
    timeline_size = 19 # in months
    
    # @months_array = Array.new
    now_dateTime = DateTime.now.to_time
    last_month = now_dateTime - 1.month
    
    temp_date_end = now_dateTime
    sql_query_end = temp_date_end.strftime("%Y-%m-01 00:00")   
    last_month_ref =  last_month.month   
    last_year_ref = last_month.year 
    
    temp_date_begin = last_month - timeline_size.month
    sql_query_begin = temp_date_begin.strftime("%Y-%m-01 00:00:00")
    first_month_ref =  temp_date_begin.strftime("%m")   
    first_year_ref = temp_date_begin.strftime("%Y")

    # REQUEST --------------------------------- 

    @charts_data = Hash.new
    charts_data_temp = Hash.new
    @titles_data = Hash.new
    charts_element.each do |chart_element|
      query = "SELECT sum(sc.average),count(sc.average),MONTH(sc.created_at),YEAR(sc.created_at) 
      FROM spider_consolidations sc,  pm_type_axes pta
      WHERE sc.pm_type_axe_id = pta.id
      AND sc.spider_id IN (" + spiders_consolidated.join(",") + ")"
      query += " AND sc.created_at >= '" + sql_query_begin.to_s + "'"
      query += " AND sc.created_at <= '" + sql_query_end.to_s + "'"
      
      if (@kpi_type == "pm_type")
        query += " AND pta.pm_type_id = " + chart_element.id.to_s
      else
        query += " AND pta.id = " + chart_element.id.to_s
      end
      
      query += " GROUP BY MONTH(created_at),YEAR(created_at) 
      ORDER BY YEAR(created_at),MONTH(created_at)";
      
      # Analyse return data
      charts_data_temp[chart_element.id.to_s] = Array.new
      charts_data_by_date = Hash.new
      
      # Save query data in hash[month-year]
      ActiveRecord::Base.connection.execute(query).each do |query_data|
        charts_data_by_date[query_data[2]+"-"+query_data[3]] = query_data
      end
      
      # Check if we have all months/years
      month_index = 0
      (Date.new(first_year_ref.to_i, first_month_ref.to_i)..Date.new(last_year_ref.to_i, last_month_ref.to_i)).select {|d| 
        if (month_index.to_i != d.month.to_i)
          if(charts_data_by_date[d.month.to_s+"-"+d.year.to_s] != nil)
            charts_data_temp[chart_element.id.to_s] << charts_data_by_date[d.month.to_s+"-"+d.year.to_s]
          else
            unassigned_month = Array.new<<0<<0<<d.month.to_i<<d.year.to_i
            charts_data_temp[chart_element.id.to_s] << unassigned_month
          end
          month_index = d.month
        end
      }
      
      # Set title
      title = lifecycle_title
      if ((@workstream != nil) and (@workstream != "0"))
        title += " - " + @workstream
      end
      if ((milestone_title != nil) and (milestone_title != ""))
        title += " - " + milestone_title.title
      end
      
      @titles_data[chart_element.id.to_s] = title + " - " + chart_element.title  
    end
    
    # Each chart
    charts_data_temp.each do |c|
      @charts_data[c[0]] = Array.new
      sum_avg = 0
      sum_count = 0
      last_avg = -1
      # Each values
      c[1].each do |cc|
        if(last_avg == -1)
            new_c = Array.new
            count_to_divise = cc[1].to_f
            if(count_to_divise == 0)
              count_to_divise = 1
            end
            new_c[0] = cc[0].to_f / count_to_divise
            last_avg = new_c[0]
            new_c[1] = cc[2]
            new_c[2] = cc[3]
            @charts_data[c[0]] << new_c
        elsif (cc[0] == 0)
            new_c = Array.new
            new_c[0] = last_avg
            last_avg = last_avg
            new_c[1] = cc[2]
            new_c[2] = cc[3]
            @charts_data[c[0]] << new_c
        elsif(last_avg == 0)
            new_c = Array.new
            count_to_divise = cc[1].to_f
            if(count_to_divise == 0)
              count_to_divise = 1
            end
            new_c[0] = cc[0].to_f / count_to_divise
            last_avg = new_c[0]
            new_c[1] = cc[2]
            new_c[2] = cc[3]
            @charts_data[c[0]] << new_c
        else
            new_c = Array.new
            new_c[0] = ((sum_avg.to_f + cc[0].to_f).to_f / (sum_count.to_f + cc[1].to_f).to_f)
            last_avg = new_c[0]
            new_c[1] = cc[2]
            new_c[2] = cc[3]
            @charts_data[c[0]] << new_c
        end    
            
        sum_avg += cc[0].to_f
        sum_count += cc[1].to_f
      end
    end
    
    if(@kpi_type_param == nil)
      render :generate_kpi_charts_data, :layout => false   
    else
      render :generate_kpi_charts_data
    end
  end
  
  # ------------------------------------------------------------------------------------
  # IMPORT FUNCTIONS
  # ------------------------------------------------------------------------------------

  # Load excel file and return the worksheet named "Conso"
  def load_spider_excel_file(post)
    redirect_to '/spiders/project_spider_import' and return if post.nil? or post['datafile'].nil?
    Spreadsheet.client_encoding = 'UTF-8'
    doc = Spreadsheet.open post['datafile']
    consoSheet = doc.worksheet 'Conso'
    return consoSheet
  end
  
  # Read the second line of the excels and return an identification of Pm type and axe for each columns
  # Return value : axesHash
  # Format : axesHash[column_index] = hash
  # axesHash[column_index]["title"] = Title of axes
  # axesHash[column_index]["type"] = Title of PM Type
  def analyze_spider_excel_file_header(consoSheet)
    # Second line of excel / Axes headers
    # Params
    subHeaderIndex = 0
    lastAxeName = ""
    axesHash = Hash.new
    
    # First line - Each Cells
    firstLineCellIndex = 0
    consoSheet.row(0).each do |sub_header_cell|
      Rails.logger.info("- - - - <>"+ sub_header_cell.to_s + "_"+ firstLineCellIndex.to_s)
      if((firstLineCellIndex > @practiceStartColumn + 1) && (sub_header_cell.to_s != ""))
        @practiceEndColumn = firstLineCellIndex - 1
        Rails.logger.info("- - - - <Pratice End>"+ @practiceEndColumn.to_s)
        @deliverableStartColumn = firstLineCellIndex
        Rails.logger.info("- - - - <Deli Start>"+ @deliverableStartColumn.to_s)
        
      end
      firstLineCellIndex += 1
    end
    @deliverableEndColumn = firstLineCellIndex - 1
    Rails.logger.info("- - - - <Deli end>"+ @deliverableEndColumn.to_s)
    
    
    # Second line - Each Cells
    consoSheet.row(1).each do |sub_header_cell|      
    	type = ""
    	if ((subHeaderIndex >= @practiceStartColumn) and (subHeaderIndex <= @practiceEndColumn))
    		type = "Practice"
    	elsif ((subHeaderIndex >= @deliverableStartColumn) and (subHeaderIndex <= @deliverableEndColumn))
    		type = "Deliverable"
    	end

      # If new axe
    	if ((type != "") and (sub_header_cell.to_s != "") and (lastAxeName != sub_header_cell.to_s))
    		axesHash[subHeaderIndex] = Hash.new
    		axesHash[subHeaderIndex]["type"] = type
    		axesHash[subHeaderIndex]["title"] = sub_header_cell.to_s
    		lastAxeName = sub_header_cell.to_s
    	elsif((type != "") and (sub_header_cell.to_s == ""))
    		axesHash[subHeaderIndex] = Hash.new
    		axesHash[subHeaderIndex]["type"] = type
    		axesHash[subHeaderIndex]["title"] = lastAxeName
    	end
    	subHeaderIndex += 1
    end
    return axesHash
  end
  
  # Read the content of excel file and return an array of hash
  # Return value : projectsArray
  # Format : projectsArray[index_array] = hash
  # projectsArray[index_array]["title"] = Name of project
  # projectsArray[index_array]["version"] = Version of project
  # projectsArray[index_array]["milestone"] = Milestone of project (can contain a string of multiple milestones. Ex : M1-M3)
  # projectsArray[index_array]["date"] = Date of project
  # projectsArray[index_array]["conso"] = Hash
  # projectsArray[index_array]["conso"][axe_name] = Hash
  # projectsArray[index_array]["conso"]["values"] = Array of values (Note + Ref + nb ni)
  # projectsArray[index_array]["conso"]["column_ids"] = Array of column id (Note column id + Ref column id + nb ni column id)
  def analyze_spider_excel_file_conso(consoSheet,axesHash)
    # Conso lines
   projectsArray = Array.new
   indexRow = 0
   # For each row
   consoSheet.each do |conso_row|
   	# If project name
   	if ((indexRow > 2) and (conso_row[3].to_s != ""))
   		projectHash = Hash.new
   		projectHash["title"] = conso_row[3].to_s
   		projectHash["version"] = conso_row[4].to_s
   		projectHash["milestone"] = conso_row[5].to_s
   		year = conso_row[8].to_i
   		year_str = year.to_s
   		month = conso_row[7].to_i
   		month_str = month.to_s
   		if (month < 10)
   		  month_str = "0"+month.to_s
   		end
   		day = conso_row[6].to_i
   		day_str = day.to_s
   		if (day < 10)
   		  day_str = "0"+day.to_s
   		end
   		projectHash["date"] = year_str+ "-" + month_str + "-" + day_str + " 00:00:00"
      projectHash["conso"] = Hash.new

   		columnIndex = 9
   		column_last_axe_name = ""
   		# For each question values/ref/ni
   		while columnIndex <= conso_row.count and columnIndex <= @deliverableEndColumn
         if(column_last_axe_name != axesHash[columnIndex]["title"])
           projectHash["conso"][axesHash[columnIndex]["title"]] = Hash.new
           projectHash["conso"][axesHash[columnIndex]["title"]]["values"] = Array.new
           projectHash["conso"][axesHash[columnIndex]["title"]]["column_ids"] = Array.new
           column_last_axe_name = axesHash[columnIndex]["title"]
         end

         projectHash["conso"][axesHash[columnIndex]["title"]]["values"] << conso_row[columnIndex].to_s
         projectHash["conso"][axesHash[columnIndex]["title"]]["column_ids"] << columnIndex.to_s
   			columnIndex += 1
   		end
   		projectsArray << projectHash
   	end
   	indexRow += 1
   end
   return projectsArray
  end

  
  
  
  ###
  # DEBUG
  ###
  def dev_project_spider_import
  end
  
  def dev_do_spider_upload
    
    # INDEX OF COLUMNS IN EXCEL ------------------------
    @practiceStartColumn = 9
    @practiceEndColumn = 0
    @deliverableStartColumn = 0
    @deliverableEndColumn = 0
    
    # LOAD FILE --------------------------------- 
    consoSheet = load_spider_excel_file(params[:upload])
    
    # ANALYSE HEADER OF FILE ---------------------------------
    axesHash = analyze_spider_excel_file_header(consoSheet)
    
    # ANALYSE CONSOS OF FILE ---------------------------------
    projectsArray = analyze_spider_excel_file_conso(consoSheet, axesHash)
    
    # IMPORT DATA IN BDD ---------------------------------
    @projectsNotFound = Array.new
    @milestonesNotFound = Array.new
    @axesNotFound = Array.new
    @projectsAdded = Array.new
    
    # For each projects
    projectsArray.each { |project| 
         	
    	# Search project in BAM
    	bam_project = Project.last(:conditions=>["name = ?", project["title"]])
    	if(bam_project == nil)
    	  bam_project = Project.new
    	  bam_project.name = project["title"]
    	  bam_project.save
    	end
    	# Search milestone
  	  milestoneList = Array.new
  	  # if (project["milestone"].count('-') > 0)
  	  #        milestoneList = project["milestone"].split('-')
  	  #      else
  	  #        milestoneList << project["milestone"]
  	  #      end 
  	  
  	  milestoneList << project["milestone"]
  	  
  	  # For each milestones of project in BAM
  	  milestoneList.each { |project_milestone|
  	    
  	    bam_milestone = Milestone.last(:conditions =>["name = ? and project_id = ?", project_milestone, bam_project.id])
  	    
  	    if(bam_milestone == nil)
  	      bam_milestone = Milestone.new
  	      bam_milestone.project_id = bam_project.id
  	      bam_milestone.name = project_milestone
  	      bam_milestone.save
  	    end 	      
    	  # Create Spider for this project
	      new_spider = create_spider_object(bam_project,bam_milestone)
	      new_spider.created_at = project["date"]
	      new_spider.save
        @projectsAdded << "Project : "+ bam_project.name + " - Milestone : " + project_milestone
	      # For each conso
	      project["conso"].each do |conso|
        
	        axe_title = conso[0]
	        if (axe_title[-1,1] == " ")
	          axe_title = axe_title[0..-2]
	        end
	        if(axe_title[0,1] == " ")
	          axe_title = axe_title[1..-1]
	        end
          pm_type = axesHash[conso[1]["column_ids"].last.to_i]["type"]
        
	        if(conso[1]["column_ids"][2].to_i <= @deliverableEndColumn)
    	      # Search type
    	      bam_pm_type = PmType.first(:conditions => ["title LIKE ?", "%"+pm_type+"%"])
  	        # Search Axes
  	        bam_axe = PmTypeAxe.first(:conditions => ["pm_type_id = ? and title LIKE ?", bam_pm_type.id, "%"+axe_title+"%"])
  	        # Axes if not found
  	        if (bam_axe != nil)
  	          # Add spider conso
  	          create_spider_history_conso(new_spider,bam_axe.id, project["date"], conso[1]["values"][0],conso[1]["values"][1],conso[1]["values"][2])
  	        else
  	          @axesNotFound << "Project : "+ bam_project.name + " - Milestone : " + project_milestone + " - Axe : " + axe_title + " not found."
  	        end
  	      end
	      end
  	  }
    }
  end
end
