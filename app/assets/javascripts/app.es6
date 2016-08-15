import {run} from '@cycle/xstream-run';
import {makeDOMDriver, div, h1, h2, button, pre} from '@cycle/dom';
import {makeHTTPDriver} from '@cycle/http';
import xs from 'xstream';
import _ from 'lodash';

function debug (v) {
  return pre(JSON.stringify(v, null, 2));
}

function renderBlock (color) {
  return (
    div('.block', {style: {background: color}})
  );
}

function renderActivity (activity) {
  return (
    div('.activity', {attrs: {'data-id': activity.id}}, [
      h2('.name', activity.name),
      div('.blocks', _.range(activity.time_blocks_per_week).map(_ => renderBlock(activity.color)))
    ])
  );
}

function view ({activities, queue}) {
  return (
    div('.view', [
      h1('Activities'),
      div('.activities', _.values(activities).map(renderActivity)),

      div('.queue', [
        div('.queue-blocks', [
          div('.blocks',
            queue.map(activity => renderBlock(activity.color))
          )
        ]),

        button('.go', 'Go')
      ])
    ])
  );
}

function updateActivities (newActivities) {
  const activities = {};

  newActivities.forEach(activity => {
    activity.blocks = _.range(activity.time_blocks_per_week).map(i => {
      return {
        key: activity + i,
        activity,
        timeRemaining: 20 * 60 * 1000
      };
    });

    activities[activity.id] = activity;
  });

  return (state) => ({...state, activities});
}

function queueBlock (activityId) {
  return (state) => {
    const activity = state.activities[activityId];

    return {
      ...state,

      queue: [...state.queue, activity]
    };
  };
}

function main ({DOM, HTTP}) {
  const activities$ = HTTP
    .select('activities')
    .flatten()
    .map(response => response.body)
    .startWith([]);

  const requestActivities$ = xs
    .of({
      url: '/activities',
      category: 'activities'
    });

  const initialState = {
    activities: [],
    queue: [],
    playing: false,
    timeRemaining: 0
  };

  const updateActivities$ = activities$
    .map(updateActivities);

  const queueBlock$ = DOM
    .select('.activity')
    .events('mousedown')
    .map(event => queueBlock(event.currentTarget.dataset.id));

  const reducer$ = xs.merge(
    queueBlock$,
    updateActivities$
  );

  const state$ = reducer$.fold((state, reducer) => reducer(state), initialState);

  return {
    DOM: state$.map(view),
    HTTP: requestActivities$
  };
}

const drivers = {
  DOM: makeDOMDriver('.app'),
  HTTP: makeHTTPDriver()
};

export default function () {
  run(main, drivers);
}
