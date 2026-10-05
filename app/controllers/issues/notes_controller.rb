# Notes on an issue's activity feed. Note bodies are encrypted at rest.
class Issues::NotesController < ApplicationController
  include IssueScoped

  def create
    @note = @issue.activities.note.new(body: note_body, user: Current.user)

    if @note.save
      respond_to_saved_note
    else
      respond_to_invalid_note
    end
  end

  private
    def note_body
      params.expect(note: [ :body ]).fetch(:body).to_s.strip
    end

    def respond_to_saved_note
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to project_issue_path(@project, @issue), status: :see_other }
      end
    end

    def respond_to_invalid_note
      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_entity }
        format.html { redirect_to project_issue_path(@project, @issue), alert: "The note couldn't be saved.", status: :see_other }
      end
    end
end
