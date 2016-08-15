import {run} from '@cycle/xstream-run';
import {makeDOMDriver, div, h1, h2, button, pre} from '@cycle/dom';
import {makeHTTPDriver} from '@cycle/http';
import xs from 'xstream';
import _ from 'lodash';

const BLOCK_WIDTH = 45;

function debug (v) {
  return pre(JSON.stringify(v, null, 2));
}

function renderBlock (block, index) {
  return (
    div('.block', {
      hero: {id: block.key},
      style: {background: block.activity.color},
      attrs: {'data-activity-id': block.activity.id}
    })
  );
}

function renderActivity (activity) {
  return (
    div('.activity', {attrs: {'data-id': activity.id}}, [
      h2('.name', activity.name),
      div('.blocks', activity.blocks.map(renderBlock))
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
            queue.map(renderBlock)
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
        key: activity.name + i,
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

    if (activity.blocks.length === 0 || state.queue.length === 5) {
      return state;
    }

    const queuedBlock = activity.blocks.slice(-1);
    const remainingBlocks = activity.blocks.slice(0, -1);

    return {
      ...state,

      activities: {
        ...state.activities,

        [activityId]: {
          ...activity,

          blocks: remainingBlocks
        }
      },

      queue: state.queue.concat(queuedBlock)
    };
  };
}

function unqueueBlock (blockElement) {
  const blockIndex = Array
    .from(blockElement.parentElement.children)
    .indexOf(blockElement);

  const activityId = blockElement.dataset.activityId;

  return function _unqueueBlock (state) {
    const newQueue = state.queue.slice();
    const unqueuedBlock = newQueue.splice(blockIndex, 1);

    const activity = state.activities[activityId];

    return {
      ...state,

      activities: {
        ...state.activities,

        [activityId]: {
          ...activity,

          blocks: activity.blocks.concat(unqueuedBlock)
        }
      },

      queue: newQueue
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

  const unqueueBlock$ = DOM
    .select('.queue .block')
    .events('mousedown')
    .map(event => unqueueBlock(event.currentTarget));

  const reducer$ = xs.merge(
    queueBlock$,
    updateActivities$,
    unqueueBlock$
  );

  const state$ = reducer$.fold((state, reducer) => reducer(state), initialState);

  return {
    DOM: state$.map(view),
    HTTP: requestActivities$
  };
}

const drivers = {
  DOM: makeDOMDriver('.app', {
    modules: [
      require('snabbdom/modules/class'),
      require('snabbdom/modules/props'),
      require('snabbdom/modules/attributes'),
      require('snabbdom/modules/eventlisteners'),
      require('snabbdom/modules/style'),
      require('snabbdom/modules/hero')
    ]
  }),
  HTTP: makeHTTPDriver()
};

export default function () {
  run(main, drivers);
}
