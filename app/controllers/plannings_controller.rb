class PlanningsController < ApplicationController

  layout 'pdc'

  def index
    @plannings = Planning.all
    id         = params[:id]
    @planning  = Planning.find_by_id(id) if id
  end

  def new
    # TODO
    Planning.create(:name=>'eLogbook')
    redirect_to :action=>'index'
  end

  def destroy
    Planning.find(params[:id]).destroy
    render(:nothing=>true)
  end

end
