defmodule Hawk.ModelPluralizationTest.Box do
  @moduledoc false

  use Hawk.Model

  model "boxes" do
    belongs_to(:school, Videdal.School)
  end
end

defmodule Hawk.ModelPluralizationTest.Category do
  @moduledoc false

  use Hawk.Model

  model "categories" do
    belongs_to(:school, Videdal.School)
  end
end

defmodule Hawk.ModelPluralizationTest.Analysis do
  @moduledoc false

  use Hawk.Model

  model "analyses" do
    belongs_to(:school, Videdal.School)
  end
end

defmodule Hawk.ModelPluralizationTest.LineItem do
  @moduledoc false

  use Hawk.Model

  model "line_items" do
    belongs_to(:school, Videdal.School)
  end
end

defmodule Hawk.ModelPluralizationTest.CustomChild do
  @moduledoc false

  use Hawk.Model

  model "custom_children" do
    belongs_to(:school, Videdal.School)
  end
end

defmodule Hawk.ModelPluralizationTest.CustomParent do
  @moduledoc false

  use Hawk.Model

  model "custom_parents" do
    has_many(:children, Hawk.ModelPluralizationTest.CustomChild, resource: Hawk.ModelPluralizationTest.CustomChildren)
  end
end

defmodule Hawk.ModelPluralizationTest do
  use ExUnit.Case, async: true

  alias Hawk.ModelPluralizationTest.Analysis
  alias Hawk.ModelPluralizationTest.Box
  alias Hawk.ModelPluralizationTest.Category
  alias Hawk.ModelPluralizationTest.CustomChildren.Policy
  alias Hawk.ModelPluralizationTest.CustomChildren.Reader
  alias Hawk.ModelPluralizationTest.CustomParent
  alias Hawk.ModelPluralizationTest.LineItem

  test "infers simple s plural resource modules" do
    assert LineItem.__hawk_resource__() == Hawk.ModelPluralizationTest.LineItems
  end

  test "infers es plural resource modules" do
    assert Box.__hawk_resource__() == Hawk.ModelPluralizationTest.Boxes
  end

  test "infers ies plural resource modules" do
    assert Category.__hawk_resource__() == Hawk.ModelPluralizationTest.Categories
  end

  test "infers irregular sis to ses plural resource modules" do
    assert Analysis.__hawk_resource__() == Hawk.ModelPluralizationTest.Analyses
  end

  test "associations can override the inferred resource base" do
    assert CustomParent.__hawk_association_policy__(:children) == {:ok, Policy}

    assert CustomParent.__hawk_association_reader__(:children) == {:ok, Reader}
  end
end
