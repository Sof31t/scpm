class Project < ActiveRecord::Base

  belongs_to  :project
  belongs_to  :supervisor, :class_name=>"Person"
  has_many    :projects, :order=>'name', :dependent=>:destroy
  has_many    :requests, :dependent=>:nullify
  has_many    :statuses, :dependent => :destroy

  def html_status
    case last_status
      when 0; "<span class='status unknown'>unknown</span>"
      when 1; "<span class='status green'>green</span>"
      when 2; "<span class='status amber'>amber</span>"
      when 3; "<span class='status red'>red</span>"
    end  
  end

  def icon_status
    case last_status
      when 0; "<img src='/images/unknown.png' align='right'>"
      when 1; "<img src='/images/green.gif' align='left'>"
      when 2; "<img src='/images/amber.gif' align='left'>"
      when 3; "<img src='/images/red.gif' align='left'>"
    end  
  end

  def has_status
    Status.find(:first, :conditions=>["project_id=?", self.id], :order=>"created_at desc")
  end
  
  def get_status
    s = has_status
    s = Status.new({:status=>0, :explanation=>"unknown"}) if not s
    s
  end

  def last_status_date
    #time_ago_in_words(get_status.updated_at)
    days_ago(get_status.updated_at)
  end
  
  def update_status(s = nil)
    if s
      self.last_status = s
      save
    end  
    propagate_status
  end

  # look at sub projects status and calculates its own
  def propagate_status
    if has_status # so if the status was green only because a green sub project (status == nil) the status wont' be updated
      status = self.last_status
    else  
      status = 0
    end
    self.projects.each { |p|
      status = p.last_status if status < p.last_status
      }
    self.last_status = status
    save
    project.propagate_status if self.project
  end
  
  def full_name
    rv = self.name
    return self.project.full_name + " > " + rv if self.project
    rv
  end
  
  
private

  def days_ago(date_time)
    return "" if date_time == nil
    Date.today() - Date.parse(date_time.to_s)
  end
end

