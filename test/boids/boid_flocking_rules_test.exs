defmodule Boids.BoidFlockingRulesTest do
  use ExUnit.Case, async: true

  alias Boids.Boid
  alias Boids.BoidFlockingConfig
  alias Boids.BoidFlockingRules

  @separation_radius BoidFlockingConfig.boid_separation_radius()

  # Every test steers this boid: in the middle of the arena, flying straight up at speed 3.
  # Unless a test says otherwise, neighbors fly the same way (see neighbor_at/2), so
  # alignment adds nothing and only the rule under test steers.
  @boid %Boid{position: {500.0, 500.0}, velocity: {0.0, -3.0}}

  @all_rules_on %{separation: true, cohesion: true, alignment: true}
  @all_rules_off %{separation: false, cohesion: false, alignment: false}

  describe "default_weights/0" do
    test "has a weight for every rule, taken from the flocking config" do
      assert BoidFlockingRules.default_weights() == %{
               separation: BoidFlockingConfig.boid_separation_weight(),
               cohesion: BoidFlockingConfig.boid_cohesion_weight(),
               alignment: BoidFlockingConfig.boid_alignment_weight()
             }
    end
  end

  describe "combined_steering_vector/4 with every rule turned on" do
    test "with no neighbors, there is no steering" do
      assert BoidFlockingRules.combined_steering_vector(@boid, [], @all_rules_on) == {0.0, 0.0}
    end

    test "multiplies each rule's vector by its weight and sums them" do
      # Close enough to separate, and flying differently, so all three rules steer.
      neighbors = [neighbor_at({490.0, 500.0}, {3.0, 0.0})]
      weights = %{separation: 3, cohesion: 0.5, alignment: 0.25}

      {separation_x, separation_y} =
        BoidFlockingRules.separation_steering_vector(@boid, neighbors)

      {cohesion_x, cohesion_y} = BoidFlockingRules.cohesion_steering_vector(@boid, neighbors)
      {alignment_x, alignment_y} = BoidFlockingRules.alignment_steering_vector(@boid, neighbors)

      assert_vector_in_delta(
        BoidFlockingRules.combined_steering_vector(@boid, neighbors, @all_rules_on, weights),
        {separation_x * 3 + cohesion_x * 0.5 + alignment_x * 0.25,
         separation_y * 3 + cohesion_y * 0.5 + alignment_y * 0.25}
      )
    end

    test "uses the default weights when none are given" do
      neighbors = [neighbor_at({490.0, 500.0}, {3.0, 0.0}), neighbor_at({530.0, 520.0})]

      assert BoidFlockingRules.combined_steering_vector(@boid, neighbors, @all_rules_on) ==
               BoidFlockingRules.combined_steering_vector(
                 @boid,
                 neighbors,
                 @all_rules_on,
                 BoidFlockingRules.default_weights()
               )
    end

    test "a rule with a weight of 0 adds nothing" do
      neighbors = [neighbor_at({490.0, 500.0}, {3.0, 0.0})]

      assert_vector_in_delta(
        BoidFlockingRules.combined_steering_vector(@boid, neighbors, @all_rules_on, %{
          separation: 1,
          cohesion: 0,
          alignment: 0
        }),
        BoidFlockingRules.separation_steering_vector(@boid, neighbors)
      )
    end

    # The next three describe the balance the default weights are tuned for. If a tuning
    # change flips one, boids will pile onto each other, never gather, or never turn
    # together.
    test "with the default weights, separation beats cohesion for a close neighbor" do
      {steering_x, _steering_y} =
        BoidFlockingRules.combined_steering_vector(
          @boid,
          [neighbor_at({490.0, 500.0})],
          @all_rules_on
        )

      assert steering_x > 0
    end

    test "with the default weights, only cohesion acts beyond the separation radius" do
      {steering_x, _steering_y} =
        BoidFlockingRules.combined_steering_vector(
          @boid,
          [neighbor_at({470.0, 500.0})],
          @all_rules_on
        )

      assert steering_x < 0
    end

    test "with the default weights, alignment turns the boid toward its neighbors' heading" do
      # Mirrored on either side beyond the separation radius, so separation and cohesion
      # cancel out, and both flying right.
      neighbors = [
        neighbor_at({470.0, 500.0}, {3.0, 0.0}),
        neighbor_at({530.0, 500.0}, {3.0, 0.0})
      ]

      {steering_x, _steering_y} =
        BoidFlockingRules.combined_steering_vector(@boid, neighbors, @all_rules_on)

      assert steering_x > 0
    end
  end

  describe "combined_steering_vector/4 rule toggles" do
    test "with every rule turned off, there is no steering, even with neighbors" do
      assert BoidFlockingRules.combined_steering_vector(
               @boid,
               steering_neighbors(),
               @all_rules_off
             ) ==
               {0.0, 0.0}
    end

    test "with only one rule turned on, the steering is just that rule's weighted vector" do
      neighbors = steering_neighbors()
      weights = %{separation: 3, cohesion: 0.5, alignment: 0.25}

      {separation_x, separation_y} =
        BoidFlockingRules.separation_steering_vector(@boid, neighbors)

      {cohesion_x, cohesion_y} = BoidFlockingRules.cohesion_steering_vector(@boid, neighbors)
      {alignment_x, alignment_y} = BoidFlockingRules.alignment_steering_vector(@boid, neighbors)

      assert_vector_in_delta(
        BoidFlockingRules.combined_steering_vector(
          @boid,
          neighbors,
          %{@all_rules_off | separation: true},
          weights
        ),
        {separation_x * 3, separation_y * 3}
      )

      assert_vector_in_delta(
        BoidFlockingRules.combined_steering_vector(
          @boid,
          neighbors,
          %{@all_rules_off | cohesion: true},
          weights
        ),
        {cohesion_x * 0.5, cohesion_y * 0.5}
      )

      assert_vector_in_delta(
        BoidFlockingRules.combined_steering_vector(
          @boid,
          neighbors,
          %{@all_rules_off | alignment: true},
          weights
        ),
        {alignment_x * 0.25, alignment_y * 0.25}
      )
    end

    test "turning one rule off removes only that rule's steering" do
      neighbors = steering_neighbors()

      {separation_x, separation_y} =
        BoidFlockingRules.separation_steering_vector(@boid, neighbors)

      {alignment_x, alignment_y} = BoidFlockingRules.alignment_steering_vector(@boid, neighbors)
      weights = BoidFlockingRules.default_weights()

      assert_vector_in_delta(
        BoidFlockingRules.combined_steering_vector(
          @boid,
          neighbors,
          %{@all_rules_on | cohesion: false}
        ),
        {separation_x * weights.separation + alignment_x * weights.alignment,
         separation_y * weights.separation + alignment_y * weights.alignment}
      )
    end

    test "a rule that is turned off is never run, so it needs no weight" do
      # Only the rules that are on look up their weight, so a weight missing for a rule
      # that is off doesn't matter. If cohesion ran, Map.fetch! would raise KeyError.
      weights_without_cohesion = %{separation: 1, alignment: 1}

      assert {_steering_x, _steering_y} =
               BoidFlockingRules.combined_steering_vector(
                 @boid,
                 steering_neighbors(),
                 %{@all_rules_on | cohesion: false},
                 weights_without_cohesion
               )
    end

    test "raises if the toggles are missing a rule, instead of treating it as off" do
      assert_raise KeyError, fn ->
        BoidFlockingRules.combined_steering_vector(
          @boid,
          steering_neighbors(),
          Map.delete(@all_rules_on, :alignment)
        )
      end
    end
  end

  describe "separation_steering_vector/2" do
    test "with no neighbors, there is no push" do
      assert BoidFlockingRules.separation_steering_vector(@boid, []) == {0.0, 0.0}
    end

    test "a neighbor to the left pushes right, with strength 1 / distance" do
      neighbors = [neighbor_at({490.0, 500.0})]

      assert_vector_in_delta(
        BoidFlockingRules.separation_steering_vector(@boid, neighbors),
        {0.1, 0.0}
      )
    end

    test "a neighbor to the right pushes left" do
      neighbors = [neighbor_at({510.0, 500.0})]

      assert_vector_in_delta(
        BoidFlockingRules.separation_steering_vector(@boid, neighbors),
        {-0.1, 0.0}
      )
    end

    test "a neighbor above pushes down (y grows downward)" do
      neighbors = [neighbor_at({500.0, 490.0})]

      assert_vector_in_delta(
        BoidFlockingRules.separation_steering_vector(@boid, neighbors),
        {0.0, 0.1}
      )
    end

    test "a closer neighbor pushes harder" do
      push_from_distance_10 =
        BoidFlockingRules.separation_steering_vector(@boid, [neighbor_at({490.0, 500.0})])

      push_from_distance_5 =
        BoidFlockingRules.separation_steering_vector(@boid, [neighbor_at({495.0, 500.0})])

      assert_vector_in_delta(push_from_distance_10, {0.1, 0.0})
      assert_vector_in_delta(push_from_distance_5, {0.2, 0.0})
    end

    test "a diagonal neighbor pushes directly away from itself, still with strength 1 / distance" do
      # A 3-4-5 triangle: the neighbor is 5 away, so the push is (3, 4) / 25 = (0.12, 0.16),
      # which has length 0.2 = 1 / 5.
      neighbors = [neighbor_at({497.0, 496.0})]

      {push_x, push_y} = push = BoidFlockingRules.separation_steering_vector(@boid, neighbors)

      assert_vector_in_delta(push, {0.12, 0.16})
      assert_in_delta :math.sqrt(push_x * push_x + push_y * push_y), 0.2, 0.0001
    end

    test "a neighbor exactly on the separation radius still pushes" do
      neighbors = [neighbor_at({500.0 - @separation_radius, 500.0})]

      assert_vector_in_delta(
        BoidFlockingRules.separation_steering_vector(@boid, neighbors),
        {1 / @separation_radius, 0.0}
      )
    end

    test "a neighbor beyond the separation radius is ignored" do
      neighbors = [neighbor_at({500.0 - @separation_radius - 1, 500.0})]

      assert BoidFlockingRules.separation_steering_vector(@boid, neighbors) == {0.0, 0.0}
    end

    test "a neighbor at exactly the same position is ignored instead of dividing by zero" do
      neighbors = [neighbor_at({500.0, 500.0})]

      assert BoidFlockingRules.separation_steering_vector(@boid, neighbors) == {0.0, 0.0}
    end

    test "equal neighbors on opposite sides cancel out" do
      neighbors = [neighbor_at({490.0, 500.0}), neighbor_at({510.0, 500.0})]

      assert_vector_in_delta(
        BoidFlockingRules.separation_steering_vector(@boid, neighbors),
        {0.0, 0.0}
      )
    end

    test "pushes are summed, not averaged, so more crowding pushes harder" do
      one_neighbor = [neighbor_at({490.0, 500.0})]
      two_neighbors_in_the_same_spot = [neighbor_at({490.0, 500.0}), neighbor_at({490.0, 500.0})]

      assert_vector_in_delta(
        BoidFlockingRules.separation_steering_vector(@boid, one_neighbor),
        {0.1, 0.0}
      )

      assert_vector_in_delta(
        BoidFlockingRules.separation_steering_vector(@boid, two_neighbors_in_the_same_spot),
        {0.2, 0.0}
      )
    end

    test "pushes from neighbors in different directions combine" do
      # Both are 10 to the left, one 5 above and one 5 below (distance² = 125). Their
      # vertical pushes cancel and their sideways pushes add: 2 x 10 / 125 = 0.16.
      neighbors = [neighbor_at({490.0, 495.0}), neighbor_at({490.0, 505.0})]

      assert_vector_in_delta(
        BoidFlockingRules.separation_steering_vector(@boid, neighbors),
        {0.16, 0.0}
      )
    end

    test "ignores the neighbors' velocities" do
      still_neighbor = %Boid{position: {490.0, 500.0}, velocity: {0.0, 0.0}}
      fast_neighbor = %Boid{position: {490.0, 500.0}, velocity: {4.0, 4.0}}

      assert BoidFlockingRules.separation_steering_vector(@boid, [still_neighbor]) ==
               BoidFlockingRules.separation_steering_vector(@boid, [fast_neighbor])
    end
  end

  describe "cohesion_steering_vector/2" do
    test "with no neighbors, there is no pull" do
      assert BoidFlockingRules.cohesion_steering_vector(@boid, []) == {0.0, 0.0}
    end

    test "with one neighbor, pulls toward it by the full distance to it" do
      neighbors = [neighbor_at({530.0, 500.0})]

      assert_vector_in_delta(
        BoidFlockingRules.cohesion_steering_vector(@boid, neighbors),
        {30.0, 0.0}
      )
    end

    test "pulls toward the average position of the neighbors" do
      # The center of these two is {470, 500}.
      neighbors = [neighbor_at({470.0, 480.0}), neighbor_at({470.0, 520.0})]

      assert_vector_in_delta(
        BoidFlockingRules.cohesion_steering_vector(@boid, neighbors),
        {-30.0, 0.0}
      )
    end

    test "pulls diagonally when the center is diagonal" do
      # The center of these two is {520, 530}.
      neighbors = [neighbor_at({510.0, 520.0}), neighbor_at({530.0, 540.0})]

      assert_vector_in_delta(
        BoidFlockingRules.cohesion_steering_vector(@boid, neighbors),
        {20.0, 30.0}
      )
    end

    test "pulls harder the farther the boid is from the center" do
      pull_from_distance_20 =
        BoidFlockingRules.cohesion_steering_vector(@boid, [neighbor_at({520.0, 500.0})])

      pull_from_distance_40 =
        BoidFlockingRules.cohesion_steering_vector(@boid, [neighbor_at({540.0, 500.0})])

      assert_vector_in_delta(pull_from_distance_20, {20.0, 0.0})
      assert_vector_in_delta(pull_from_distance_40, {40.0, 0.0})
    end

    test "a boid already at the center of its neighbors is not pulled" do
      neighbors = [neighbor_at({470.0, 500.0}), neighbor_at({530.0, 500.0})]

      assert_vector_in_delta(
        BoidFlockingRules.cohesion_steering_vector(@boid, neighbors),
        {0.0, 0.0}
      )
    end

    test "the pull depends on where the center is, not on how many neighbors there are" do
      one_neighbor = [neighbor_at({530.0, 500.0})]

      three_neighbors_in_the_same_spot = [
        neighbor_at({530.0, 500.0}),
        neighbor_at({530.0, 500.0}),
        neighbor_at({530.0, 500.0})
      ]

      assert_vector_in_delta(
        BoidFlockingRules.cohesion_steering_vector(@boid, three_neighbors_in_the_same_spot),
        BoidFlockingRules.cohesion_steering_vector(@boid, one_neighbor)
      )
    end

    test "counts neighbors inside the separation radius too" do
      neighbors = [neighbor_at({505.0, 500.0})]

      assert_vector_in_delta(
        BoidFlockingRules.cohesion_steering_vector(@boid, neighbors),
        {5.0, 0.0}
      )
    end

    test "ignores the neighbors' velocities" do
      still_neighbor = %Boid{position: {530.0, 500.0}, velocity: {0.0, 0.0}}
      fast_neighbor = %Boid{position: {530.0, 500.0}, velocity: {4.0, 4.0}}

      assert BoidFlockingRules.cohesion_steering_vector(@boid, [still_neighbor]) ==
               BoidFlockingRules.cohesion_steering_vector(@boid, [fast_neighbor])
    end
  end

  describe "alignment_steering_vector/2" do
    test "with no neighbors, there is no steering" do
      assert BoidFlockingRules.alignment_steering_vector(@boid, []) == {0.0, 0.0}
    end

    test "with neighbors already flying the same way, there is no steering" do
      neighbors = [neighbor_at({490.0, 500.0}), neighbor_at({530.0, 520.0})]

      assert_vector_in_delta(
        BoidFlockingRules.alignment_steering_vector(@boid, neighbors),
        {0.0, 0.0}
      )
    end

    test "steers by the difference between the neighbor's velocity and the boid's" do
      # The boid flies up at {0, -3}; the neighbor flies right at {3, 0}.
      # {3, 0} - {0, -3} = {3, 3}: cancel the upward motion, add rightward motion.
      neighbors = [neighbor_at({530.0, 500.0}, {3.0, 0.0})]

      assert_vector_in_delta(
        BoidFlockingRules.alignment_steering_vector(@boid, neighbors),
        {3.0, 3.0}
      )
    end

    test "steers toward the average velocity of several neighbors" do
      # The average of {2, 0} and {0, -2} is {1, -1}; {1, -1} - {0, -3} = {1, 2}.
      neighbors = [
        neighbor_at({530.0, 500.0}, {2.0, 0.0}),
        neighbor_at({470.0, 500.0}, {0.0, -2.0})
      ]

      assert_vector_in_delta(
        BoidFlockingRules.alignment_steering_vector(@boid, neighbors),
        {1.0, 2.0}
      )
    end

    test "neighbors whose average matches the boid cause no steering, even if each differs" do
      # The average of {3, -3} and {-3, -3} is {0, -3}, the boid's own velocity.
      neighbors = [
        neighbor_at({530.0, 500.0}, {3.0, -3.0}),
        neighbor_at({470.0, 500.0}, {-3.0, -3.0})
      ]

      assert_vector_in_delta(
        BoidFlockingRules.alignment_steering_vector(@boid, neighbors),
        {0.0, 0.0}
      )
    end

    test "steers hardest against neighbors flying the opposite way" do
      # {0, 3} - {0, -3} = {0, 6}.
      neighbors = [neighbor_at({530.0, 500.0}, {0.0, 3.0})]

      assert_vector_in_delta(
        BoidFlockingRules.alignment_steering_vector(@boid, neighbors),
        {0.0, 6.0}
      )
    end

    test "matches the neighbors' speed, not just their direction" do
      # Same direction but faster: {0, -4} - {0, -3} = {0, -1}, so the boid speeds up.
      neighbors = [neighbor_at({530.0, 500.0}, {0.0, -4.0})]

      assert_vector_in_delta(
        BoidFlockingRules.alignment_steering_vector(@boid, neighbors),
        {0.0, -1.0}
      )
    end

    test "the steering depends on the average velocity, not on how many neighbors there are" do
      one_neighbor = [neighbor_at({530.0, 500.0}, {3.0, 0.0})]

      three_neighbors_flying_the_same_way = [
        neighbor_at({530.0, 500.0}, {3.0, 0.0}),
        neighbor_at({470.0, 500.0}, {3.0, 0.0}),
        neighbor_at({500.0, 530.0}, {3.0, 0.0})
      ]

      assert_vector_in_delta(
        BoidFlockingRules.alignment_steering_vector(@boid, three_neighbors_flying_the_same_way),
        BoidFlockingRules.alignment_steering_vector(@boid, one_neighbor)
      )
    end

    test "ignores the neighbors' positions" do
      near_neighbor = neighbor_at({505.0, 500.0}, {3.0, 0.0})
      far_neighbor = neighbor_at({540.0, 520.0}, {3.0, 0.0})

      assert BoidFlockingRules.alignment_steering_vector(@boid, [near_neighbor]) ==
               BoidFlockingRules.alignment_steering_vector(@boid, [far_neighbor])
    end
  end

  # Defaults to flying the same way as @boid, so alignment adds nothing unless a test
  # gives the neighbor a different velocity.
  # Close enough to separate, and flying a different way, so every rule steers when on.
  defp steering_neighbors, do: [neighbor_at({490.0, 500.0}, {3.0, 0.0})]

  defp neighbor_at(position, velocity \\ {0.0, -3.0}),
    do: %Boid{position: position, velocity: velocity}

  defp assert_vector_in_delta({actual_x, actual_y}, {expected_x, expected_y}) do
    assert_in_delta actual_x, expected_x, 0.0001
    assert_in_delta actual_y, expected_y, 0.0001
  end
end
