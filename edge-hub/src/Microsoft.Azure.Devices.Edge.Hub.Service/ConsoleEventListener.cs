// Copyright (c) Microsoft. All rights reserved.

/*
 * To read colorized logs, analyze timings use https://marketplace.visualstudio.com/items?itemName=emilast.LogFileHighlighter
 *
 * Suggested color configuration :

   "logFileHighlighter.customPatterns": [
        {
            "pattern": ".*-Enter]",
            "foreground": "#42adf4"
        },
        {
            "pattern": ".*-Exit]",
            "foreground": "#cc99ff"
        },
        {
            "pattern": ".*-Associate]",
            "foreground": "magenta"
        },
        {
            "pattern": ".*-Info]",
            "foreground": "#11a046"
        },
        {
            "pattern": ".*-ErrorMessage]",
            "foreground": "red"
        },
        {
            "pattern": ".*-Critical]",
            "foreground": "#ea4112"
        },
        {
            "pattern": ".*-TestMessage]",
            "foreground": "gray"
        },
    ]
 *
 */

namespace System.Diagnostics.Tracing
{
    public sealed class ConsoleEventListener : EventListener
    {
        private readonly string[] _eventFilters;
        private object _lock = new object();

        public ConsoleEventListener()
            : this(string.Empty)
        {
        }

        public ConsoleEventListener(string filter)
        {
            this._eventFilters = new string[1];
            this._eventFilters[0] = filter ?? throw new ArgumentNullException(nameof(filter));

            this.InitializeEventSources();
        }

        public ConsoleEventListener(string[] filters)
        {
            this._eventFilters = filters ?? throw new ArgumentNullException(nameof(filters));
            if (this._eventFilters.Length == 0)
                throw new ArgumentException("Filters cannot be empty");

            foreach (string filter in this._eventFilters)
            {
                if (string.IsNullOrWhiteSpace(filter))
                {
                    throw new ArgumentNullException(nameof(filters));
                }
            }

            this.InitializeEventSources();
        }

        private void InitializeEventSources()
        {
            foreach (EventSource source in EventSource.GetSources())
            {
                this.EnableEvents(source, EventLevel.LogAlways);
            }
        }

        protected override void OnEventSourceCreated(EventSource eventSource)
        {
            base.OnEventSourceCreated(eventSource);
#if NET451
            EnableEvents(eventSource, EventLevel.LogAlways);
#else
            this.EnableEvents(eventSource, EventLevel.LogAlways, EventKeywords.All);
#endif
        }

        protected override void OnEventWritten(EventWrittenEventArgs eventData)
        {
            if (this._eventFilters == null)
                return;

            lock (this._lock)
            {
                bool shouldDisplay = false;

                if (this._eventFilters.Length == 1 && eventData.EventSource.Name.StartsWith(this._eventFilters[0]))
                {
                    shouldDisplay = true;
                }
                else
                {
                    foreach (string filter in this._eventFilters)
                    {
                        if (eventData.EventSource.Name.StartsWith(filter))
                        {
                            shouldDisplay = true;
                        }
                    }
                }

                if (shouldDisplay)
                {
#if NET451
                    string text = $"{DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss.fffffff")} [{eventData.EventSource.Name}-{eventData.EventId}]{(eventData.Payload != null ? $" ({string.Join(", ", eventData.Payload)})." : "")}";
#else
                    string text = $"{DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss.fffffff")} [{eventData.EventSource.Name}-{eventData.EventName}]{(eventData.Payload != null ? $" ({string.Join(", ", eventData.Payload)})." : string.Empty)}";
#endif

                    ConsoleColor origForeground = Console.ForegroundColor;
                    Console.ForegroundColor = ConsoleColor.DarkYellow;
                    Console.WriteLine(text);
                    Debug.WriteLine(text);
                    Console.ForegroundColor = origForeground;
                }
            }
        }
    }
}
