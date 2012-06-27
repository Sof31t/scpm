# import SDP
# make a SDP export to Excel and save it as *.csv
#Identifiant,Phase/Activit�/T�che,Charge,,,Cons.,Reste � Faire,Charge r�vis�e,Charge acquise,It�ration,Collab,Solde,,
#,,estim�e,R�-�valu�e,Attribu�e,,,,,,,Initial,R�-�valu�,Attribu�

require 'csv'

class SDP

  ID          = 0
  TITLE       = 1
  INTIAL      = 3
  REEVALUATED = 4
  ASSIGNED    = 5
  CONSUMED    = 6
  REMAINING   = 7
  REVISED     = 8
  GAINED      = 9
  ITERATION   = 10
  COLLAB      = 11
  BALANCEI    = 12
  BALANCER    = 13
  BALANCEA    = 14

	def initialize(path)
    @path = path
	end

  def import
    @reader = CSV.open(@path, 'r')

    # skip 2 first lines
    @reader.shift
    @reader.shift
    ActiveRecord::Base.connection.execute("TRUNCATE sdp_phases")
    ActiveRecord::Base.connection.execute("TRUNCATE sdp_activities")
    ActiveRecord::Base.connection.execute("TRUNCATE sdp_tasks")
    @state = :init
    while true
      if @next_row == nil
        @row = @reader.shift
      else
        @row = @next_row
        @next_row = nil
      end
      break if @row.empty?
      insert
      break if @state == :end
    end
  end

private

  def sanitize(name)
    return nil if not name
    name.gsub!(160.chr,"")
    name.strip
  end

  def populate(p)
    p.initial     = @row[INTIAL]
    p.reevaluated = @row[REEVALUATED]
    p.assigned    = @row[ASSIGNED]
    p.consumed    = @row[CONSUMED]
    p.remaining   = @row[REMAINING]
    p.revised     = @row[REVISED]
    p.gained      = @row[GAINED]
    p.iteration   = @row[ITERATION]
    p.collab      = @row[COLLAB]
    p.balancei    = @row[BALANCEI]
    p.balancer    = @row[BALANCER]
    p.balancea    = @row[BALANCEA]
  end

  def create_phase
    t = sanitize(@row[TITLE])
    return if t == nil
    #p = SDPPhase.find_by_title(t)
    p = SDPPhase.new# if not p
    p.title = t
    populate(p)
    p.save
    @current_phase = p
  end

  def create_activity
    t = sanitize(@row[TITLE])
    return if t == nil
    #p = SDPActivity.find_by_title_and_phase_id(t,@current_phase.id)
    p = SDPActivity.new# if not p
    p.phase_id = @current_phase.id
    p.title = t
    populate(p)
    p.save
    @current_activity = p
  end

  def create_task
    t = sanitize(@row[TITLE])
    return if t == nil
    #p = SDPTask.find_by_sdp_id(@row[ID])
    p = SDPTask.new# if not p
    p.phase_id    = @current_phase.id
    p.activity_id = @current_activity.id
    p.sdp_id = @row[ID]
    p.title  = t
    r_id = /^\[(\d+)\].*$/.match(t)
    p.request_id = r_id[1] if r_id
    
    # don't save sdp task if RMT request is cancelled and sdp set to no
    save_task = true
    if r_id
      task_request = Request.first(:conditions=>["request_id = ?",r_id[1]])
      if task_request.status == "cancelled" and task_request.sdp == "No"
        save_task = false
      end
    end
    if save_task
      populate(p)
      p.save
    else
      remove_task_from_activity
      remove_task_from_phase
    end
  end

  def remove_task_from_activity
    @current_activity.initial -= @row[INTIAL].to_f
    @current_activity.reevaluated -= @row[REEVALUATED].to_f
    @current_activity.assigned -= @row[ASSIGNED].to_f
    @current_activity.consumed -= @row[CONSUMED].to_f
    @current_activity.remaining -= @row[REMAINING].to_f
    @current_activity.revised -= @row[REVISED].to_f
    @current_activity.gained -= @row[GAINED].to_f
    @current_activity.balancei -= @row[BALANCEI].to_f
    @current_activity.balancer -= @row[BALANCER].to_f
    @current_activity.balancea -= @row[BALANCEA].to_f
    @current_activity.save
  end
  
  def remove_task_from_phase
    @current_phase.initial -= @row[INTIAL].to_f
    @current_phase.reevaluated -= @row[REEVALUATED].to_f
    @current_phase.assigned -= @row[ASSIGNED].to_f
    @current_phase.consumed -= @row[CONSUMED].to_f
    @current_phase.remaining -= @row[REMAINING].to_f
    @current_phase.revised -= @row[REVISED].to_f
    @current_phase.gained -= @row[GAINED].to_f
    @current_phase.balancei -= @row[BALANCEI].to_f
    @current_phase.balancer -= @row[BALANCER].to_f
    @current_phase.balancea -= @row[BALANCEA].to_f
    @current_phase.save
  end
  
  def insert
    #puts @row.join(', ')
    #puts @row[ID]
    if @row[ID]==nil
      case @state
        when :init;  @state = :phase
        when :phase; @state = :activity
        when :task
          @next_row = @reader.shift
          if @next_row[ID] == nil
            @state = :phase
          else
            @state = :activity
          end
        when :total
          @state = :end
        else; raise "state error #{@state.to_s}"
      end
    elsif @row[ID]=="Total"
      @state = :total
    else
      @state = :task
    end
    case @state
      when :phase
        create_phase
      when :activity
        create_activity
      when :task
        create_task
      when :total
        @state = :end
      else; raise "state error #{@state.to_s}"
    end
  end

end

#=begin
#i = Sdp.new('C:\Users\faivremacon\My Documents\Downloads\SDP.csv')
#i.import
#=end

