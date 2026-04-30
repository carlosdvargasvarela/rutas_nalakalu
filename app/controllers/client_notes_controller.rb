# app/controllers/client_notes_controller.rb
class ClientNotesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client
  before_action :set_note, only: [:update, :destroy]

  def create
    @note = @client.client_notes.build(note_params)
    @note.user = current_user
    authorize @note

    if @note.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.prepend(
              "client_notes_list",
              partial: "client_notes/note",
              locals: {note: @note}
            ),
            turbo_stream.replace(
              "client_notes_badge_#{@client.id}",
              partial: "client_notes/badge",
              locals: {client: @client}
            ),
            turbo_stream.replace(
              "client_pinned_notes_#{@client.id}",
              partial: "client_notes/pinned_banner",
              locals: {client: @client}
            ),
            turbo_stream.replace(
              "client_note_form",
              partial: "client_notes/form",
              locals: {client: @client, note: ClientNote.new}
            )
          ]
        end
        format.html { redirect_to client_path(@client), notice: "Nota agregada." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "client_note_form",
            partial: "client_notes/form",
            locals: {client: @client, note: @note}
          ), status: :unprocessable_entity
        end
        format.html { redirect_to client_path(@client), alert: "Error al guardar la nota." }
      end
    end
  end

  def update
    authorize @note

    if @note.update(note_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "client_note_#{@note.id}",
              partial: "client_notes/note",
              locals: {note: @note}
            ),
            turbo_stream.replace(
              "client_pinned_notes_#{@client.id}",
              partial: "client_notes/pinned_banner",
              locals: {client: @client}
            )
          ]
        end
        format.html { redirect_to client_path(@client), notice: "Nota actualizada." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "client_note_#{@note.id}",
            partial: "client_notes/note_edit_form",
            locals: {client: @client, note: @note}
          ), status: :unprocessable_entity
        end
        format.html { redirect_to client_path(@client), alert: "Error al actualizar la nota." }
      end
    end
  end

  def destroy
    authorize @note
    @note.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("client_note_#{@note.id}"),
          turbo_stream.replace(
            "client_notes_badge_#{@client.id}",
            partial: "client_notes/badge",
            locals: {client: @client}
          ),
          turbo_stream.replace(
            "client_pinned_notes_#{@client.id}",
            partial: "client_notes/pinned_banner",
            locals: {client: @client}
          )
        ]
      end
      format.html { redirect_to client_path(@client), notice: "Nota eliminada." }
    end
  end

  private

  def set_client
    @client = Client.find(params[:client_id])
  end

  def set_note
    @note = @client.client_notes.find(params[:id])
  end

  def note_params
    params.require(:client_note).permit(:body, :category, :pinned)
  end
end
