import {run} from '@cycle/xstream-run';
import {makeDOMDriver, div, h1, h2, button, pre} from '@cycle/dom';
import {makeHTTPDriver} from '@cycle/http';
import timeDriver from './drivers/time-driver.es6';
import xs from 'xstream';
import _ from 'lodash';
const BLOCK_WIDTH = 45;

function debug (v) {
  return pre(JSON.stringify(v, null, 2));
}

function renderFullscreenBlock (block) {
  return (
    div('.block.fullscreen', {
      hero: {id: block.key},
      style: {background: block.activity.color},
      attrs: {'data-activity-id': block.activity.id}
    })
  );
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

const views = {
  'activities': activitiesView,
  'timer': playingView
};

function view (state) {
  if (views[state.view] === undefined) {
    throw new Error(`Cannot find a view for "${state.view}".`);
  };

  return views[state.view](state);
}

function activitiesView ({activities, queue, playing}) {
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

        button('.go', {props: {disabled: queue.length === 0}}, 'Start')
      ])
    ])
  );
}

function prettyTime (timeInMsec) {
  const minutes = Math.floor(timeInMsec / 60 / 1000);
  const seconds = Math.floor(((timeInMsec / 60 / 1000) - minutes) * 60);

  return `${_.padStart(minutes, 2, '0')}:${_.padStart(seconds, 2, '0')}`;
}

function playingView ({activities, queue, playing}) {
  return (
    div('.view', [
      h1('.activity-name', queue[0].activity.name),

      h1(`${prettyTime(queue[0].timeRemaining)} left`),

      renderFullscreenBlock(queue[0]),

      div('.queue', [
        div('.queue-blocks', [
          div('.blocks',
            queue.slice(1).map(renderBlock)
          )
        ]),

        button('.pause', 'Pause')
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
        timeRemaining: 0.1 * 60 * 1000
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

function go () {
  return function _go (state) {
    return {
      ...state,

      view: 'timer',
      playing: true
    };
  };
}

function countdown (delta) {
  return function _countdown (state) {
    if (!state.playing || state.view !== 'timer') {
      return state;
    }

    const [currentBlock, ...remainingBlocks] = state.queue;

    const updatedBlock = {
      ...currentBlock,

      timeRemaining: currentBlock.timeRemaining - delta
    };

    if (updatedBlock.timeRemaining > 0) {
      return {
        ...state,

        queue: [updatedBlock, ...remainingBlocks]
      };
    }

    if (remainingBlocks.length === 0) {
      return {
        ...state,

        queue: [],

        playing: false,
        view: 'activities'
      };
    }

    // Implicitly, we are removing the block and there are remainingBlocks
    return {
      ...state,

      queue: [...remainingBlocks]

      // TODO: update the server somehow to say we've done a thing
    };
  };
}

function main ({DOM, HTTP, Time}) {
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
    view: 'activities',
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

  const go$ = DOM
    .select('.go')
    .events('click')
    .map(go);

  const countdown$ = Time
    .map(({delta}) => delta)
    .map(delta => countdown(delta));

  const reducer$ = xs.merge(
    queueBlock$,
    updateActivities$,
    unqueueBlock$,
    go$,
    countdown$
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
  HTTP: makeHTTPDriver(),
  Time: timeDriver
};

export default function () {
  run(main, drivers);
}
