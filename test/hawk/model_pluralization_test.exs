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
    has_many(:children, Hawk.ModelPluralizationTest.CustomChild,
      resource: Hawk.ModelPluralizationTest.CustomChildren
    )
  end
end

defmodule Hawk.ModelPluralizationTest do
  use ExUnit.Case, async: true

  test "infers simple s plural resource modules" do
    assert Hawk.ModelPluralizationTest.LineItem.__hawk_resource__() ==
             Hawk.ModelPluralizationTest.LineItems
  end

  test "infers es plural resource modules" do
    assert Hawk.ModelPluralizationTest.Box.__hawk_resource__() ==
             Hawk.ModelPluralizationTest.Boxes
  end

  test "infers ies plural resource modules" do
    assert Hawk.ModelPluralizationTest.Category.__hawk_resource__() ==
             Hawk.ModelPluralizationTest.Categories
  end

  test "infers irregular sis to ses plural resource modules" do
    assert Hawk.ModelPluralizationTest.Analysis.__hawk_resource__() ==
             Hawk.ModelPluralizationTest.Analyses
  end

  test "associations can override the inferred resource base" do
    assert Hawk.ModelPluralizationTest.CustomParent.__hawk_association_policy__(:children) ==
             {:ok, Hawk.ModelPluralizationTest.CustomChildren.Policy}

    assert Hawk.ModelPluralizationTest.CustomParent.__hawk_association_reader__(:children) ==
             {:ok, Hawk.ModelPluralizationTest.CustomChildren.Reader}
  end
end
