require "test_helper"

class ContactsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get new_contact_url
    assert_response :success
  end

  test "should create contact" do
    assert_difference("Contact.count", 1) do
      post contacts_url, params: {
        contact: {
          name: "Test User",
          email: "test@example.com",
          message: "Test message"
        }
      }
    end

    assert_redirected_to new_contact_url
  end
end
