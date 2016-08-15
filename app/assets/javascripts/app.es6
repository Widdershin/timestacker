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
      style: {background: block.activity.color, transform: `translateX(${index * BLOCK_WIDTH}px)`},
      attrs: {'data-activity-id': block.activity.id}
    })
  );
}

function renderActiveBlock (block) {
  return (
    div('.block.active', {
      style: {background: block.activity.color, 'box-shadow': `0px 0px 5px 1px ${block.activity.color}`},
      attrs: {'data-activity-id': block.activity.id}
    })
  );
}

function renderActivity (activity) {
  return (
    div('.activity', {attrs: {'data-id': activity.id}}, [
      div('.name-container', [
        div('.activity-name', {hero: {id: activity.name}}, activity.name),
      ]),
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
  }

  return views[state.view](state);
}

const fadeInOutStyle = {
  opacity: '0', delayed: {opacity: '1'}, remove: {opacity: '0'}
};

function activitiesView ({activities, queue, playing}) {
  return (
    div('.view.activities', {style: fadeInOutStyle}, [
      h1('Activities'),
      div('.activities', _.values(activities).map(renderActivity)),

      div('.queue', [
        div('.queue-blocks', [
          div('.blocks',
            queue.map(renderBlock)
          )
        ])
      ]),

      button('.control.go', {props: {disabled: queue.length === 0}}, 'Start')
    ])
  );
}

function timeRemaining (queue) {
  const currentBlock = queue[0];

  return _(queue)
    .takeWhile(block => block.activity.id === currentBlock.activity.id)
    .map('timeRemaining')
    .sum();
}

function prettyTime (timeInMsec) {
  const minutes = Math.floor(timeInMsec / 60 / 1000);
  const seconds = Math.floor(((timeInMsec / 60 / 1000) - minutes) * 60);

  return `${_.padStart(minutes, 2, '0')}:${_.padStart(seconds, 2, '0')}`;
}

function playingView ({activities, queue, playing}) {
  return (
    div('.view.playing', {style: fadeInOutStyle}, [
      div('.activity-name', {hero: {id: queue[0].activity.name}}, queue[0].activity.name),

      h1(`${prettyTime(timeRemaining(queue))} left`),

      renderFullscreenBlock(queue[0]),

      div('.queue', [
        div('.queue-blocks', [
          div('.blocks',
            renderActiveBlock(queue[0]),
            queue.map((block, index) => index === 0 ? renderActiveBlock(block) : renderBlock(block, index))
          )
        ])
      ]),

      button('.control.back', 'Back'),

      playing ?
        button('.control.pause', 'Pause') :
        button('.control.go', 'Play')
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

    if (activity.blocks.length === 0 || state.queue.length === 6) {
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
    if (state.view !== 'activities') {
      return state;
    }

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

function pause () {
  return function _pause (state) {
    return {
      ...state,

      playing: false
    };
  };
}

function backToActivities () {
  return function _backToActivities (state) {
    return {
      ...state,

      playing: false,
      view: 'activities'
    }
  }
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

  const pause$ = DOM
    .select('.pause')
    .events('click')
    .map(pause);

  const backToActivities$ = DOM
    .select('.back')
    .events('click')
    .map(backToActivities);

  const countdown$ = Time
    .map(({delta}) => delta)
    .map(delta => countdown(delta));

  const reducer$ = xs.merge(
    queueBlock$,
    updateActivities$,
    unqueueBlock$,
    go$,
    pause$,
    countdown$,
    backToActivities$
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
