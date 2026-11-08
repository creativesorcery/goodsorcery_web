# The three-step stepper on the setup page. Step 1 (create) is always done;
# step 2 (install) is current until the first event lands, after which every
# step is done and the project counts as connected.
class SetupProgress
  Step = Data.define(:number, :label, :state) do
    def done? = state == :done
    def current? = state == :current
  end

  STEP_COUNT = 3
  INSTALL_STEP = 2

  attr_reader :project

  def initialize(project)
    @project = project
  end

  def connected? = !project.listening?

  def steps
    labels.each_with_index.map { |label, index| Step.new(number: index + 1, label:, state: state_of(index + 1)) }
  end

  def current_step
    steps.find(&:current?)
  end

  # "Step 2 of 3", or "Connected" once the first event arrived.
  def eyebrow
    connected? ? "Connected" : "Step #{current_step.number} of #{STEP_COUNT}"
  end

  private
    # "Install the gem", or "Install the crate" for Rust.
    def labels = [ "Create project", "Install the #{project.client_package}", "Receive first event" ]

    def state_of(number)
      return :done if number == 1 || connected?

      number == INSTALL_STEP ? :current : :pending
    end
end
